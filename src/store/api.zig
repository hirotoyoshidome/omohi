const std = @import("std");

const PersistenceLayout = @import("./object/persistence_layout.zig").PersistenceLayout;
const local_tracked = @import("./local/tracked.zig");
const local_staged = @import("./local/staged.zig");
const local_snapshot = @import("./local/snapshot.zig");
const local_commit = @import("./local/commit.zig");
const local_tags = @import("./local/tags.zig");
const local_commit_tags = @import("./local/commit_tags.zig");
const local_trash = @import("./local/trash.zig");
const local_head = @import("./local/head.zig");
const version_guard = @import("./storage/version_guard.zig");
const ContentEntry = @import("./object/content_entry.zig").ContentEntry;
const api_types = @import("./object/api_types.zig");
const hash = @import("./object/hash.zig");
const lock = @import("./storage/lock.zig");
const utc = @import("./storage/time/utc.zig");
const constrained_types = @import("./object/constrained_types.zig");

const max_add_file_size = 64 * 1024 * 1024;

pub const StatusKind = api_types.StatusKind;
pub const StatusEntry = api_types.StatusEntry;
pub const StatusList = api_types.StatusList;
pub const CommitSummary = api_types.CommitSummary;
pub const CommitSummaryList = api_types.CommitSummaryList;
pub const TagList = api_types.TagList;
pub const CommitDetails = api_types.CommitDetails;
pub const TrackedEntry = local_tracked.TrackedEntry;
pub const TrackedList = local_tracked.TrackedList;
pub const StoreVersionOptions = version_guard.Options;
pub const expected_store_version = version_guard.expected_store_version;

/// Validates store VERSION and optionally bootstraps VERSION for empty store.
pub fn ensureStoreVersion(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    options: StoreVersionOptions,
) !void {
    try version_guard.ensureStoreVersion(allocator, omohi_dir, options);
}

/// Store facade API for ops layer.
/// The facade hides store internals (object/storage/local).
///
/// Planned public APIs (initial draft):
/// - initOmohiDirIfNeeded
/// - track, untrack
/// - add, rm
/// - commit
/// - status, tracklist
/// - find, show
/// - tagAdd, tagRemove, tagList
///
/// Adds a file into staging and writes both entry and staged object.
/// Memory: borrowed (allocator is only used for temporary allocations)
/// Errors: lock/I/O errors, error{FileTooLarge}, and constrained type errors.
pub fn add(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    source_dir: std.fs.Dir,
    source_path: []const u8,
) !void {
    try lock.acquireLock(omohi_dir);
    defer lock.releaseLock(omohi_dir);

    const persistence = PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.stagedEntriesPath());
    try omohi_dir.makePath(persistence.stagedObjectsPath());

    const content_hash = try contentHashFromFile(allocator, source_dir, source_path);
    const entry_path = try std.fmt.allocPrint(
        allocator,
        "/objects/{s}/{s}",
        .{ content_hash[0..2], content_hash[0..] },
    );
    defer allocator.free(entry_path);

    const entry = ContentEntry{
        .path = try constrained_types.ContentPath.init(entry_path),
        .content_hash = try constrained_types.ContentHash.init(&content_hash),
    };
    const staged_file_id = hash.stagedFileIdFrom(source_path, &content_hash);

    try local_staged.writeStagedEntry(allocator, persistence, &staged_file_id, entry);
    try local_staged.copyFileToStagedObject(allocator, persistence, source_dir, source_path, &content_hash);
}

/// Removes a staged entry/object pair by file path.
/// Memory: borrowed
/// Errors: error{NotFound} plus lock/I/O and constrained type errors.
pub fn rm(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    source_dir: std.fs.Dir,
    source_path: []const u8,
) !void {
    try lock.acquireLock(omohi_dir);
    defer lock.releaseLock(omohi_dir);

    const persistence = PersistenceLayout.init(omohi_dir);
    const content_hash = try contentHashFromFile(allocator, source_dir, source_path);
    const staged_file_id = hash.stagedFileIdFrom(source_path, &content_hash);

    local_trash.moveStagedEntryToTrash(allocator, persistence, &staged_file_id) catch |err| switch (err) {
        error.FileNotFound => return error.NotFound,
        else => return err,
    };

    var has_same_hash = false;
    var entries = local_staged.loadStagedEntries(allocator, persistence) catch |err| switch (err) {
        error.MissingStagedEntries => null,
        else => return err,
    };
    defer if (entries) |*list| local_staged.freeEntries(allocator, list);

    if (entries) |*list| {
        for (list.items) |entry| {
            if (std.mem.eql(u8, entry.content_hash.asSlice(), &content_hash)) {
                has_same_hash = true;
                break;
            }
        }
    }

    if (!has_same_hash) {
        local_trash.moveStagedObjectToTrash(allocator, persistence, &content_hash) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }
}

/// Registers an absolute file path under tracked/<TrackedFileId>.
/// Memory: borrowed (temporary allocations only)
/// Errors: error{AlreadyTracked} plus lock/I/O and constrained type errors.
pub fn track(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !constrained_types.TrackedFileId {
    try lock.acquireLock(omohi_dir);
    defer lock.releaseLock(omohi_dir);

    const persistence = PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.trackedPath());
    try omohi_dir.makePath(persistence.trackedTrashPath());

    _ = try constrained_types.TrackedFilePath.init(absolute_path);

    var existing = try loadTrackedOrEmpty(allocator, persistence);
    defer if (existing) |*list| local_tracked.freeTrackedList(allocator, list);

    if (existing) |*list| {
        for (list.items) |entry| {
            if (std.mem.eql(u8, entry.path.asSlice(), absolute_path)) return error.AlreadyTracked;
        }
    }

    const tracked_id = constrained_types.TrackedFileId.generate();
    try local_tracked.writeTracked(allocator, persistence, tracked_id.asSlice(), absolute_path);
    return tracked_id;
}

/// Removes a tracked file by moving tracked/<id> into tracked/.trash/<id>.
/// Memory: borrowed
/// Errors: error{NotFound} plus lock/I/O and constrained type errors.
pub fn untrack(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    tracked_file_id: []const u8,
) !void {
    const id = try constrained_types.TrackedFileId.init(tracked_file_id);

    try lock.acquireLock(omohi_dir);
    defer lock.releaseLock(omohi_dir);

    const persistence = PersistenceLayout.init(omohi_dir);
    const tracked_path = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}",
        .{ persistence.trackedPath(), id.asSlice() },
    );
    defer allocator.free(tracked_path);

    var file = omohi_dir.openFile(tracked_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.NotFound,
        else => return err,
    };
    file.close();

    try local_tracked.deleteTracked(allocator, persistence, id.asSlice());
}

/// Loads current tracked entries from tracked/.
/// Memory: owned list, free with freeTracklist.
pub fn tracklist(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !local_tracked.TrackedList {
    const persistence = PersistenceLayout.init(omohi_dir);
    return (try loadTrackedOrEmpty(allocator, persistence)) orelse TrackedList.init(allocator);
}

pub fn freeTracklist(allocator: std.mem.Allocator, list: *TrackedList) void {
    local_tracked.freeTrackedList(allocator, list);
}

/// Computes status for tracked files.
/// Memory: owned list, free with freeStatusList.
pub fn status(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !StatusList {
    var results = StatusList.init(allocator);
    errdefer freeStatusList(allocator, &results);

    const persistence = PersistenceLayout.init(omohi_dir);
    var tracked = try tracklist(allocator, omohi_dir);
    defer freeTracklist(allocator, &tracked);

    var committed_hashes = std.AutoHashMap([64]u8, void).init(allocator);
    defer committed_hashes.deinit();

    if (try headCommitId(allocator, persistence)) |head_id| {
        var details = try show(allocator, omohi_dir, head_id.asSlice());
        defer freeCommitDetails(allocator, &details);
        for (details.entries.items) |entry| {
            try committed_hashes.put(entry.content_hash.value, {});
        }
    }

    for (tracked.items) |tracked_entry| {
        const path_owned = try allocator.dupe(u8, tracked_entry.path.asSlice());
        errdefer allocator.free(path_owned);

        var kind: StatusKind = .tracked;

        const file = std.fs.openFileAbsolute(tracked_entry.path.asSlice(), .{}) catch null;
        if (file) |tracked_file| {
            var mutable_file = tracked_file;
            defer mutable_file.close();

            const current_hash = try contentHashFromOpenedFile(allocator, mutable_file);
            const staged_id = hash.stagedFileIdFrom(tracked_entry.path.asSlice(), &current_hash);
            if (try hasStagedEntry(allocator, persistence, &staged_id)) {
                kind = .staged;
            } else if (committed_hashes.contains(current_hash)) {
                kind = .committed;
            } else if (committed_hashes.count() != 0) {
                kind = .changed;
            }
        }

        try results.append(.{
            .id = tracked_entry.id,
            .path = path_owned,
            .status = kind,
        });
    }

    return results;
}

pub fn freeStatusList(allocator: std.mem.Allocator, list: *StatusList) void {
    for (list.items) |entry| allocator.free(entry.path);
    list.deinit();
}

/// Finds commits with optional tag and date filters.
/// Date format is YYYY-MM-DD and compared with createdAt prefix.
pub fn find(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    tag_name: ?[]const u8,
    date_prefix: ?[]const u8,
) !CommitSummaryList {
    var out = CommitSummaryList.init(allocator);
    errdefer freeCommitSummaryList(allocator, &out);

    const persistence = PersistenceLayout.init(omohi_dir);
    var commit_ids = try listCommitIds(allocator, persistence);
    defer commit_ids.deinit();

    for (commit_ids.items) |commit_id_buf| {
        const parsed = try readCommitFile(allocator, persistence, commit_id_buf[0..]);
        errdefer freeParsedCommit(allocator, &parsed);

        if (date_prefix) |prefix| {
            if (!std.mem.startsWith(u8, parsed.created_at, prefix)) {
                freeParsedCommit(allocator, &parsed);
                continue;
            }
        }

        if (tag_name) |needle| {
            if (!try commitHasTag(allocator, persistence, commit_id_buf[0..], needle)) {
                freeParsedCommit(allocator, &parsed);
                continue;
            }
        }

        try out.append(.{
            .commit_id = parsed.commit_id,
            .message = parsed.message,
            .created_at = parsed.created_at,
        });
    }

    return out;
}

pub fn freeCommitSummaryList(allocator: std.mem.Allocator, list: *CommitSummaryList) void {
    for (list.items) |item| {
        allocator.free(item.message);
        allocator.free(item.created_at);
    }
    list.deinit();
}

/// Loads commit detail including snapshot entries and tags.
pub fn show(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    commit_id: []const u8,
) !CommitDetails {
    const persistence = PersistenceLayout.init(omohi_dir);
    const parsed = try readCommitFile(allocator, persistence, commit_id);
    errdefer freeParsedCommit(allocator, &parsed);

    var entries = try readSnapshotEntries(allocator, persistence, parsed.snapshot_id.asSlice());
    errdefer freeContentEntryList(allocator, &entries);

    var tags = TagList.init(allocator);
    errdefer freeTagList(allocator, &tags);

    const commit_tags = local_commit_tags.readCommitTags(allocator, persistence, parsed.commit_id.asSlice()) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };

    if (commit_tags) |record| {
        defer {
            var mutable = record;
            mutable.deinit(allocator);
        }
        for (record.tags.items) |tag| try tags.append(try allocator.dupe(u8, tag));
    }

    return .{
        .commit_id = parsed.commit_id,
        .snapshot_id = parsed.snapshot_id,
        .message = parsed.message,
        .created_at = parsed.created_at,
        .entries = entries,
        .tags = tags,
    };
}

pub fn freeCommitDetails(allocator: std.mem.Allocator, details: *CommitDetails) void {
    allocator.free(details.message);
    allocator.free(details.created_at);
    freeContentEntryList(allocator, &details.entries);
    freeTagList(allocator, &details.tags);
}

pub fn tagList(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    commit_id: []const u8,
) !TagList {
    const persistence = PersistenceLayout.init(omohi_dir);
    _ = try constrained_types.CommitId.init(commit_id);

    var tags = TagList.init(allocator);
    errdefer freeTagList(allocator, &tags);

    const record = local_commit_tags.readCommitTags(allocator, persistence, commit_id) catch |err| switch (err) {
        error.FileNotFound => return tags,
        else => return err,
    };
    defer {
        var mutable = record;
        mutable.deinit(allocator);
    }

    for (record.tags.items) |tag| {
        try tags.append(try allocator.dupe(u8, tag));
    }
    return tags;
}

pub fn freeTagList(allocator: std.mem.Allocator, tags: *TagList) void {
    for (tags.items) |tag| allocator.free(tag);
    tags.deinit();
}

pub fn tagAdd(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    commit_id: []const u8,
    tag_names: []const []const u8,
) !void {
    const id = try constrained_types.CommitId.init(commit_id);

    try lock.acquireLock(omohi_dir);
    defer lock.releaseLock(omohi_dir);

    const persistence = PersistenceLayout.init(omohi_dir);
    try ensureCommitExists(allocator, persistence, id.asSlice());
    try omohi_dir.makePath(persistence.dataTagsPath());

    var merged = TagList.init(allocator);
    defer freeTagList(allocator, &merged);

    const existing = local_commit_tags.readCommitTags(allocator, persistence, id.asSlice()) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (existing) |record| {
        var mutable = record;
        mutable.deinit(allocator);
    };

    if (existing) |record| {
        for (record.tags.items) |tag| try merged.append(try allocator.dupe(u8, tag));
    }

    for (tag_names) |tag_name| {
        _ = try constrained_types.TagName.init(tag_name);
        if (!containsTag(merged.items, tag_name)) {
            try merged.append(try allocator.dupe(u8, tag_name));
        }

        const now = try utc.nowIso8601Utc();
        const maybe_created = local_tags.readTagCreatedAt(allocator, persistence, tag_name) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (maybe_created) |created| {
            allocator.free(created);
        } else {
            try local_tags.writeTag(allocator, persistence, tag_name, now[0..]);
        }
    }

    const now = try utc.nowIso8601Utc();
    const created_at = if (existing) |record| record.created_at else now[0..];

    const tag_views = try allocator.alloc([]const u8, merged.items.len);
    defer allocator.free(tag_views);
    for (merged.items, 0..) |tag, idx| tag_views[idx] = tag;

    try local_commit_tags.writeCommitTags(
        allocator,
        persistence,
        id.asSlice(),
        tag_views,
        created_at,
        now[0..],
    );
}

pub fn tagRemove(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    commit_id: []const u8,
    tag_names: []const []const u8,
) !void {
    const id = try constrained_types.CommitId.init(commit_id);

    try lock.acquireLock(omohi_dir);
    defer lock.releaseLock(omohi_dir);

    const persistence = PersistenceLayout.init(omohi_dir);
    try ensureCommitExists(allocator, persistence, id.asSlice());

    var record = local_commit_tags.readCommitTags(allocator, persistence, id.asSlice()) catch |err| switch (err) {
        error.FileNotFound => return error.NotFound,
        else => return err,
    };
    defer record.deinit(allocator);

    for (tag_names) |tag_name| _ = try constrained_types.TagName.init(tag_name);

    var remaining = TagList.init(allocator);
    defer freeTagList(allocator, &remaining);

    for (record.tags.items) |tag| {
        if (!containsTag(tag_names, tag)) try remaining.append(try allocator.dupe(u8, tag));
    }

    if (remaining.items.len == 0) {
        try local_commit_tags.deleteCommitTags(allocator, persistence, id.asSlice());
        return;
    }

    const now = try utc.nowIso8601Utc();
    const tag_views = try allocator.alloc([]const u8, remaining.items.len);
    defer allocator.free(tag_views);
    for (remaining.items, 0..) |tag, idx| tag_views[idx] = tag;

    try local_commit_tags.writeCommitTags(
        allocator,
        persistence,
        id.asSlice(),
        tag_views,
        record.created_at,
        now[0..],
    );
}

/// Executes the durable commit transaction: lock -> persist data -> HEAD -> cleanup.
/// Memory: borrowed (allocator used for temporary allocations only)
/// Errors: error{NothingToCommit}, underlying I/O or lock errors.
pub fn commit(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    message: []const u8,
) !constrained_types.CommitId {
    try lock.acquireLock(omohi_dir);
    defer lock.releaseLock(omohi_dir);

    const persistence = PersistenceLayout.init(omohi_dir);

    var entries = try local_staged.loadStagedEntries(allocator, persistence);
    defer local_staged.freeEntries(allocator, &entries);

    if (entries.items.len == 0) return error.NothingToCommit;

    std.mem.sort(ContentEntry, entries.items, {}, isPathLessThan);

    const snapshot_id = try hash.snapshotIdFrom(allocator, entries.items);
    const commit_id = hash.commitIdFrom(snapshot_id[0..], message);

    try local_snapshot.writeSnapshot(allocator, persistence, snapshot_id[0..], entries.items);
    try local_commit.writeCommit(allocator, persistence, commit_id[0..], snapshot_id[0..], message);

    try local_staged.moveObjectsFromStage(allocator, persistence);
    try local_head.writeHead(allocator, persistence, commit_id[0..]);
    try local_staged.resetStaged(persistence);
    return try constrained_types.CommitId.init(commit_id[0..]);
}

fn isPathLessThan(_: void, lhs: ContentEntry, rhs: ContentEntry) bool {
    return ContentEntry.isPathLessThan(lhs, rhs);
}

const ParsedCommit = struct {
    commit_id: constrained_types.CommitId,
    snapshot_id: constrained_types.SnapshotId,
    message: []u8,
    created_at: []u8,
};

fn readCommitFile(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    commit_id: []const u8,
) !ParsedCommit {
    const id = try constrained_types.CommitId.init(commit_id);

    const path = try persistence.commitsPath(allocator, id.asSlice());
    defer allocator.free(path);

    const bytes = try persistence.dir.readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(bytes);

    const snapshot_raw = propertyValue(bytes, "snapshotId") orelse return error.InvalidCommit;
    const message_raw = propertyValue(bytes, "message") orelse return error.InvalidCommit;
    const created_raw = propertyValue(bytes, "createdAt") orelse return error.InvalidCommit;

    return .{
        .commit_id = id,
        .snapshot_id = try constrained_types.SnapshotId.init(snapshot_raw),
        .message = try allocator.dupe(u8, message_raw),
        .created_at = try allocator.dupe(u8, created_raw),
    };
}

fn freeParsedCommit(allocator: std.mem.Allocator, parsed: *const ParsedCommit) void {
    allocator.free(parsed.message);
    allocator.free(parsed.created_at);
}

fn readSnapshotEntries(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    snapshot_id: []const u8,
) !std.array_list.Managed(ContentEntry) {
    _ = try constrained_types.SnapshotId.init(snapshot_id);

    const path = try persistence.snapshotsPath(allocator, snapshot_id);
    defer allocator.free(path);

    const bytes = try persistence.dir.readFileAlloc(allocator, path, 4 * 1024 * 1024);
    defer allocator.free(bytes);

    const count_raw = propertyValue(bytes, "entries.count") orelse return error.InvalidSnapshot;
    const count = try std.fmt.parseInt(usize, count_raw, 10);

    var out = std.array_list.Managed(ContentEntry).init(allocator);
    errdefer freeContentEntryList(allocator, &out);

    var index: usize = 0;
    while (index < count) : (index += 1) {
        const key_path = try std.fmt.allocPrint(allocator, "entry.{d}.path", .{index});
        defer allocator.free(key_path);
        const key_hash = try std.fmt.allocPrint(allocator, "entry.{d}.contentHash", .{index});
        defer allocator.free(key_hash);

        const raw_path = propertyValue(bytes, key_path) orelse return error.InvalidSnapshot;
        const raw_hash = propertyValue(bytes, key_hash) orelse return error.InvalidSnapshot;

        const path_owned = try allocator.dupe(u8, raw_path);
        errdefer allocator.free(path_owned);

        try out.append(.{
            .path = try constrained_types.ContentPath.init(path_owned),
            .content_hash = try constrained_types.ContentHash.init(raw_hash),
        });
    }

    return out;
}

fn freeContentEntryList(allocator: std.mem.Allocator, entries: *std.array_list.Managed(ContentEntry)) void {
    for (entries.items) |entry| allocator.free(@constCast(entry.path.asSlice()));
    entries.deinit();
}

fn propertyValue(bytes: []const u8, key: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, bytes, '\n');
    while (iter.next()) |raw| {
        const line = std.mem.trim(u8, std.mem.trimRight(u8, raw, "\r"), " \t");
        if (line.len <= key.len or line[key.len] != '=') continue;
        if (!std.mem.startsWith(u8, line, key)) continue;
        return line[key.len + 1 ..];
    }
    return null;
}

fn listCommitIds(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
) !std.array_list.Managed([64]u8) {
    var list = std.array_list.Managed([64]u8).init(allocator);
    errdefer list.deinit();

    var base = persistence.dir.openDir("commits", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return list,
        else => return err,
    };
    defer base.close();

    var it = base.iterate();
    while (try it.next()) |prefix| {
        if (prefix.kind != .directory) continue;
        if (!isTwoHex(prefix.name)) continue;

        var shard = try base.openDir(prefix.name, .{ .iterate = true });
        defer shard.close();

        var shard_it = shard.iterate();
        while (try shard_it.next()) |entry| {
            if (entry.kind != .file) continue;
            var id: [64]u8 = undefined;
            try copyHexId(entry.name, &id, error.InvalidCommitId);
            try list.append(id);
        }
    }

    std.mem.sort([64]u8, list.items, {}, isCommitIdDescLessThan);
    return list;
}

fn isCommitIdDescLessThan(_: void, lhs: [64]u8, rhs: [64]u8) bool {
    return std.mem.order(u8, &lhs, &rhs) == .gt;
}

fn isTwoHex(input: []const u8) bool {
    if (input.len != 2) return false;
    return std.ascii.isHex(input[0]) and std.ascii.isHex(input[1]);
}

fn copyHexId(source: []const u8, out: *[64]u8, comptime err_tag: anytype) !void {
    if (source.len != out.len) return err_tag;
    for (source, 0..) |ch, idx| {
        if (!std.ascii.isHex(ch)) return err_tag;
        out[idx] = std.ascii.toLower(ch);
    }
}

fn commitHasTag(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    commit_id: []const u8,
    tag_name: []const u8,
) !bool {
    const record = local_commit_tags.readCommitTags(allocator, persistence, commit_id) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer {
        var mutable = record;
        mutable.deinit(allocator);
    }

    for (record.tags.items) |tag| {
        if (std.mem.eql(u8, tag, tag_name)) return true;
    }
    return false;
}

fn ensureCommitExists(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    commit_id: []const u8,
) !void {
    const path = try persistence.commitsPath(allocator, commit_id);
    defer allocator.free(path);

    var file = persistence.dir.openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.CommitNotFound,
        else => return err,
    };
    file.close();
}

fn containsTag(list: []const []const u8, target: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, target)) return true;
    }
    return false;
}

fn headCommitId(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
) !?constrained_types.CommitId {
    const bytes = persistence.dir.readFileAlloc(allocator, persistence.headPath(), 256) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(bytes);

    const commit_id = propertyValue(bytes, "commitId") orelse return error.InvalidHead;
    return try constrained_types.CommitId.init(commit_id);
}

fn hasStagedEntry(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    staged_file_id: []const u8,
) !bool {
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.stagedEntriesPath(), staged_file_id });
    defer allocator.free(path);

    var file = persistence.dir.openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    file.close();
    return true;
}

fn contentHashFromFile(
    allocator: std.mem.Allocator,
    source_dir: std.fs.Dir,
    source_path: []const u8,
) ![64]u8 {
    var source_file = try source_dir.openFile(source_path, .{});
    defer source_file.close();

    return contentHashFromOpenedFile(allocator, source_file);
}

fn contentHashFromOpenedFile(
    allocator: std.mem.Allocator,
    source_file: std.fs.File,
) ![64]u8 {
    const stat = try source_file.stat();
    const file_size = std.math.cast(usize, stat.size) orelse return error.FileTooLarge;
    if (file_size > max_add_file_size) return error.FileTooLarge;
    const max_bytes = @max(file_size, @as(usize, 1));

    const bytes = try source_file.readToEndAlloc(allocator, max_bytes);
    defer allocator.free(bytes);

    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, bytes);

    return hash.sha256Hex(encoded);
}

fn loadTrackedOrEmpty(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
) !?TrackedList {
    return local_tracked.loadTracked(allocator, persistence) catch |err| switch (err) {
        error.MissingTracked => null,
        else => return err,
    };
}

test "track writes tracked entry and tracklist returns it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const tracked_id = try track(allocator, omohi_dir, "/tmp/tracked-a.txt");
    try std.testing.expectEqual(@as(usize, 32), tracked_id.asSlice().len);

    const tracked_path = try std.fmt.allocPrint(allocator, "tracked/{s}", .{tracked_id.asSlice()});
    defer allocator.free(tracked_path);
    const bytes = try omohi_dir.readFileAlloc(allocator, tracked_path, 256);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings("/tmp/tracked-a.txt", bytes);

    var list = try tracklist(allocator, omohi_dir);
    defer freeTracklist(allocator, &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("/tmp/tracked-a.txt", list.items[0].path.asSlice());
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("LOCK", .{}));
}

test "track rejects duplicate absolute path and releases lock" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    _ = try track(allocator, omohi_dir, "/tmp/same.txt");
    try std.testing.expectError(error.AlreadyTracked, track(allocator, omohi_dir, "/tmp/same.txt"));
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("LOCK", .{}));
}

test "untrack moves tracked file into trash and missing id returns NotFound" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const tracked_id = try track(allocator, omohi_dir, "/tmp/remove-me.txt");
    try untrack(allocator, omohi_dir, tracked_id.asSlice());

    const src_path = try std.fmt.allocPrint(allocator, "tracked/{s}", .{tracked_id.asSlice()});
    defer allocator.free(src_path);
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile(src_path, .{}));

    const trash_path = try std.fmt.allocPrint(allocator, "tracked/.trash/{s}", .{tracked_id.asSlice()});
    defer allocator.free(trash_path);
    const bytes = try omohi_dir.readFileAlloc(allocator, trash_path, 256);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings("/tmp/remove-me.txt", bytes);

    try std.testing.expectError(error.NotFound, untrack(allocator, omohi_dir, tracked_id.asSlice()));
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("LOCK", .{}));
}

test "tracklist returns empty when tracked directory does not exist" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var list = try tracklist(allocator, omohi_dir);
    defer freeTracklist(allocator, &list);
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
}

test "content hash uses sha256 of base64-encoded file bytes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();

    var source_file = try source_dir.createFile("memo.txt", .{});
    try source_file.writeAll("hello add");
    source_file.close();

    const content_hash = try contentHashFromFile(allocator, source_dir, "memo.txt");
    const expected = hash.sha256Hex("aGVsbG8gYWRk");
    try std.testing.expectEqualSlices(u8, expected[0..], content_hash[0..]);
}
