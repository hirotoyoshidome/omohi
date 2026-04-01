const std = @import("std");
const builtin = @import("builtin");

const PersistenceLayout = @import("./object/persistence_layout.zig").PersistenceLayout;
const local_tracked = @import("./local/tracked.zig");
const local_staged = @import("./local/staged.zig");
const local_snapshot = @import("./local/snapshot.zig");
const local_commit = @import("./local/commit.zig");
const local_tags = @import("./local/tags.zig");
const local_commit_tags = @import("./local/commit_tags.zig");
const local_trash = @import("./local/trash.zig");
const local_head = @import("./local/head.zig");
const local_journal = @import("./local/journal.zig");
const local_version = @import("./local/version.zig");
const version_guard = @import("./storage/version_guard.zig");
const ContentEntry = @import("./object/content_entry.zig").ContentEntry;
const api_types = @import("./object/api_types.zig");
const hash = @import("./object/hash.zig");
const lock = @import("./storage/lock.zig");
const utc = @import("./storage/time/utc.zig");
const local_date = @import("./storage/time/local_date.zig");
const local_timestamp = @import("./storage/time/local_timestamp.zig");
const constrained_types = @import("./object/constrained_types.zig");

const max_add_file_size = 64 * 1024 * 1024;

const CommitFailurePoint = enum {
    none,
    before_write_snapshot,
    before_write_commit,
    before_move_objects,
    before_write_head,
    before_reset_staged,
};

var commit_failure_point: CommitFailurePoint = .none;

pub const StatusKind = api_types.StatusKind;
pub const StatusEntry = api_types.StatusEntry;
pub const StatusList = api_types.StatusList;
pub const CommitSummary = api_types.CommitSummary;
pub const CommitSummaryList = api_types.CommitSummaryList;
pub const StringList = api_types.StringList;
pub const TagList = api_types.TagList;
pub const CommitDetails = api_types.CommitDetails;
pub const TrackedEntry = local_tracked.TrackedEntry;
pub const TrackedList = local_tracked.TrackedList;
pub const StagedEntry = local_staged.StagedEntry;

/// Validates store VERSION.
pub fn ensureStoreVersion(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !void {
    try version_guard.ensureStoreVersion(allocator, omohi_dir);
}

/// Initializes VERSION for first track only.
pub fn initializeVersionForFirstTrack(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !void {
    const persistence = PersistenceLayout.init(omohi_dir);
    var file = omohi_dir.openFile(persistence.versionPath(), .{}) catch |err| switch (err) {
        error.FileNotFound => {
            if (!try isStoreEmpty(omohi_dir)) return error.MissingStoreVersion;
            try local_version.writeVersion(allocator, persistence, version_guard.expected_store_version);
            return;
        },
        else => return err,
    };
    file.close();
}

/// Appends one successful command event into journal.
pub fn appendJournal(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    command_type: []const u8,
    payload_json: []const u8,
) !void {
    const persistence = PersistenceLayout.init(omohi_dir);
    const ts_millis = std.time.milliTimestamp();
    const ts_utc = try utc.iso8601FromMillis(ts_millis);
    const local_ts = try local_timestamp.iso8601FromMillisLocal(ts_millis);

    try local_journal.appendRecord(allocator, persistence, .{
        .ts_utc = ts_utc,
        .local_ts = local_ts,
        .command_type = command_type,
        .payload_json = payload_json,
    });
}

fn isStoreEmpty(omohi_dir: std.fs.Dir) !bool {
    var it = omohi_dir.iterate();
    while (try it.next()) |_| return false;
    return true;
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
/// Errors: lock/I/O errors, error{TrackedFileNotFound, FileTooLarge}, and constrained type errors.
pub fn add(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !void {
    try lock.acquireLock(omohi_dir);
    defer lock.releaseLock(omohi_dir);

    const persistence = PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.stagedEntriesPath());
    try omohi_dir.makePath(persistence.stagedObjectsPath());

    _ = try constrained_types.TrackedFilePath.init(absolute_path);
    const tracked_entry = try requireTrackedEntryByPath(allocator, persistence, absolute_path);

    const source_parent = std.fs.path.dirname(absolute_path) orelse return error.InvalidPath;
    const source_name = std.fs.path.basename(absolute_path);
    if (source_name.len == 0) return error.InvalidPath;

    var source_dir = try std.fs.openDirAbsolute(source_parent, .{});
    defer source_dir.close();

    var staged_entries = loadStagedEntriesOrEmpty(allocator, persistence) catch |err| switch (err) {
        error.MissingStagedEntries => null,
        else => return err,
    };
    defer if (staged_entries) |*list| local_staged.freeEntries(allocator, list);

    const content_hash = try contentHashFromFile(allocator, source_dir, source_name);
    if (try headContentHashForPath(allocator, persistence, absolute_path)) |head_hash| {
        if (std.mem.eql(u8, head_hash.asSlice(), &content_hash)) {
            try unstagePathIfPresent(allocator, persistence, staged_entries, absolute_path);
            return;
        }
    }

    if (staged_entries) |list| {
        if (local_staged.findByPath(list.items, absolute_path)) |existing_entry| {
            if (std.mem.eql(u8, existing_entry.content_hash.asSlice(), &content_hash)) return;
            try unstageEntry(allocator, persistence, staged_entries, existing_entry);
        }
    }

    const entry = StagedEntry{
        .path = try constrained_types.TrackedFilePath.init(absolute_path),
        .tracked_file_id = tracked_entry.id,
        .content_hash = try constrained_types.ContentHash.init(&content_hash),
    };
    const staged_file_id = hash.stagedFileIdFrom(absolute_path, &content_hash);

    try local_staged.writeStagedEntry(allocator, persistence, &staged_file_id, entry);
    try local_staged.copyFileToStagedObject(allocator, persistence, source_dir, source_name, &content_hash);
}

/// Removes a staged entry/object pair by file path.
/// Memory: borrowed
/// Errors: error{TrackedFileNotFound, StagedFileNotFound} plus lock/I/O and constrained type errors.
pub fn rm(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !void {
    try lock.acquireLock(omohi_dir);
    defer lock.releaseLock(omohi_dir);

    const persistence = PersistenceLayout.init(omohi_dir);
    _ = try constrained_types.TrackedFilePath.init(absolute_path);
    _ = try requireTrackedEntryByPath(allocator, persistence, absolute_path);

    var staged_entries = loadStagedEntriesOrEmpty(allocator, persistence) catch |err| switch (err) {
        error.MissingStagedEntries => null,
        else => return err,
    };
    defer if (staged_entries) |*list| local_staged.freeEntries(allocator, list);

    if (staged_entries) |list| {
        if (local_staged.findByPath(list.items, absolute_path)) |entry| {
            try unstageEntry(allocator, persistence, staged_entries, entry);
            return;
        }
    }

    return error.StagedFileNotFound;
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
    try ensureTrackTargetIsNotDirectory(absolute_path);

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

    var head_entries = try loadHeadSnapshotEntries(allocator, omohi_dir, persistence);
    defer if (head_entries) |*list| freeContentEntryList(allocator, list);

    var staged_entries = loadStagedEntriesOrEmpty(allocator, persistence) catch |err| switch (err) {
        error.MissingStagedEntries => null,
        else => return err,
    };
    defer if (staged_entries) |*list| local_staged.freeEntries(allocator, list);

    for (tracked.items) |tracked_entry| {
        const path_owned = try allocator.dupe(u8, tracked_entry.path.asSlice());
        errdefer allocator.free(path_owned);

        var kind: StatusKind = .tracked;

        const file = std.fs.openFileAbsolute(tracked_entry.path.asSlice(), .{}) catch null;
        if (file) |tracked_file| {
            var mutable_file = tracked_file;
            defer mutable_file.close();

            const stat = mutable_file.stat() catch null;
            if (stat) |file_stat| {
                if (file_stat.kind == .file) {
                    const current_hash = try contentHashFromOpenedFile(allocator, mutable_file);
                    if (staged_entries) |list| {
                        if (local_staged.findByPath(list.items, tracked_entry.path.asSlice())) |entry| {
                            if (std.mem.eql(u8, entry.content_hash.asSlice(), &current_hash)) {
                                kind = .staged;
                            } else {
                                kind = .changed;
                            }
                        } else if (findContentEntryByPath(head_entries, tracked_entry.path.asSlice())) |head_entry| {
                            const head_hash = head_entry.content_hash;
                            if (std.mem.eql(u8, head_hash.asSlice(), &current_hash)) {
                                kind = .committed;
                            } else {
                                kind = .changed;
                            }
                        } else if (head_entries != null) {
                            kind = .changed;
                        }
                    } else if (findContentEntryByPath(head_entries, tracked_entry.path.asSlice())) |head_entry| {
                        const head_hash = head_entry.content_hash;
                        if (std.mem.eql(u8, head_hash.asSlice(), &current_hash)) {
                            kind = .committed;
                        } else {
                            kind = .changed;
                        }
                    } else if (head_entries != null) {
                        kind = .changed;
                    }
                }
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
/// Date format is YYYY-MM-DD and compared against createdAt in local timezone.
pub fn find(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    tag_name: ?[]const u8,
    date_ymd: ?[]const u8,
) !CommitSummaryList {
    var out = CommitSummaryList.init(allocator);
    errdefer freeCommitSummaryList(allocator, &out);

    const persistence = PersistenceLayout.init(omohi_dir);
    var commit_ids = try listCommitIds(allocator, persistence);
    defer commit_ids.deinit();

    var matches = std.array_list.Managed(FindCandidate).init(allocator);
    defer freeFindCandidates(allocator, &matches);

    for (commit_ids.items) |commit_id_buf| {
        const parsed = try readCommitFile(allocator, persistence, commit_id_buf[0..]);
        errdefer freeParsedCommit(allocator, &parsed);

        const created_at_millis = local_date.parseUtcIso8601Millis(parsed.created_at) catch |err| switch (err) {
            error.InvalidTimestamp, error.TimestampBeforeEpoch, error.TimestampOutOfRange => return error.InvalidCommit,
        };

        if (date_ymd) |target_date| {
            const local_ymd = local_date.utcIso8601ToLocalYmd(parsed.created_at) catch |err| switch (err) {
                error.InvalidTimestamp, error.TimestampBeforeEpoch, error.TimestampOutOfRange, error.LocaltimeFailed => return error.InvalidCommit,
            };
            if (!std.mem.eql(u8, local_ymd[0..], target_date)) {
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

        try matches.append(.{
            .parsed = parsed,
            .created_at_millis = created_at_millis,
        });
    }

    std.mem.sort(FindCandidate, matches.items, {}, isFindCandidateDescLessThan);

    const max_results: usize = 10;
    const keep_count = @min(matches.items.len, max_results);
    var idx: usize = 0;
    while (idx < keep_count) : (idx += 1) {
        const candidate = matches.items[idx];
        try out.append(.{
            .commit_id = candidate.parsed.commit_id,
            .message = try allocator.dupe(u8, candidate.parsed.message),
            .created_at = try allocator.dupe(u8, candidate.parsed.created_at),
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
    const parsed = readCommitFile(allocator, persistence, commit_id) catch |err| switch (err) {
        error.FileNotFound => return error.CommitNotFound,
        else => return err,
    };
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
    const id = try constrained_types.CommitId.init(commit_id);
    try ensureCommitExists(allocator, persistence, id.asSlice());

    var tags = TagList.init(allocator);
    errdefer freeTagList(allocator, &tags);

    const record = local_commit_tags.readCommitTags(allocator, persistence, id.asSlice()) catch |err| switch (err) {
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

pub fn freeStringList(allocator: std.mem.Allocator, list: *StringList) void {
    for (list.items) |item| allocator.free(item);
    list.deinit();
}

/// Loads latest journal lines in reverse chronological order.
/// Memory: owned list, free with freeStringList.
pub fn journal(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    limit: usize,
) !StringList {
    const persistence = PersistenceLayout.init(omohi_dir);
    return local_journal.readLatestLines(allocator, persistence, limit);
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

/// Lists commit IDs sorted descending.
/// Memory: owned
/// Lifetime: valid until caller frees with freeStringList
/// Errors: I/O and validation errors
pub fn commitIdList(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !StringList {
    const persistence = PersistenceLayout.init(omohi_dir);
    var ids = try listCommitIds(allocator, persistence);
    defer ids.deinit();

    var out = StringList.init(allocator);
    errdefer freeStringList(allocator, &out);

    for (ids.items) |id| {
        try out.append(try allocator.dupe(u8, &id));
    }
    return out;
}

/// Lists global tag names sorted ascending.
/// Memory: owned
/// Lifetime: valid until caller frees with freeStringList
/// Errors: I/O and validation errors
pub fn tagNameList(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !StringList {
    const persistence = PersistenceLayout.init(omohi_dir);
    return try loadTagNameList(allocator, persistence);
}

/// Lists staged paths sorted ascending.
/// Memory: owned
/// Lifetime: valid until caller frees with freeStringList
/// Errors: I/O and validation errors
pub fn stagedPathList(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !StringList {
    var statuses = try status(allocator, omohi_dir);
    defer freeStatusList(allocator, &statuses);

    var out = StringList.init(allocator);
    errdefer freeStringList(allocator, &out);

    for (statuses.items) |entry| {
        if (entry.status != .staged) continue;
        try out.append(try allocator.dupe(u8, entry.path));
    }
    std.mem.sort([]u8, out.items, {}, isStringAscLessThan);
    return out;
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

    try local_staged.ensureObjectsExistForEntries(allocator, persistence, entries.items);

    var snapshot_entries = try local_staged.snapshotEntriesFromStaged(allocator, entries.items);
    defer local_staged.freeSnapshotEntries(allocator, &snapshot_entries);
    std.mem.sort(ContentEntry, snapshot_entries.items, {}, isPathLessThan);

    const snapshot_id = try hash.snapshotIdFrom(allocator, snapshot_entries.items);
    const commit_id = hash.commitIdFrom(snapshot_id[0..], message);

    try maybeFailCommitAt(.before_write_snapshot);
    try local_snapshot.writeSnapshot(allocator, persistence, snapshot_id[0..], snapshot_entries.items);
    try maybeFailCommitAt(.before_write_commit);
    try local_commit.writeCommit(allocator, persistence, commit_id[0..], snapshot_id[0..], message);

    try maybeFailCommitAt(.before_move_objects);
    try local_staged.moveObjectsFromStage(allocator, persistence);
    try maybeFailCommitAt(.before_write_head);
    try local_head.writeHead(allocator, persistence, commit_id[0..]);
    try maybeFailCommitAt(.before_reset_staged);
    try local_staged.resetStaged(persistence);
    return try constrained_types.CommitId.init(commit_id[0..]);
}

fn maybeFailCommitAt(point: CommitFailurePoint) !void {
    if (!builtin.is_test) return;
    if (commit_failure_point == point) return error.TestInjectedFailure;
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

const FindCandidate = struct {
    parsed: ParsedCommit,
    created_at_millis: i64,
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

fn freeFindCandidates(allocator: std.mem.Allocator, candidates: *std.array_list.Managed(FindCandidate)) void {
    for (candidates.items) |candidate| freeParsedCommit(allocator, &candidate.parsed);
    candidates.deinit();
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

    var out = std.array_list.Managed(ContentEntry).init(allocator);
    errdefer freeContentEntryList(allocator, &out);

    const entries_raw = propertyValue(bytes, "entries") orelse return error.InvalidSnapshot;
    const entries_value = std.mem.trim(u8, entries_raw, " \t");
    if (entries_value.len == 0) return out;

    var pair_iter = std.mem.splitScalar(u8, entries_value, ',');
    while (pair_iter.next()) |pair_raw| {
        const pair = std.mem.trim(u8, pair_raw, " \t");
        if (pair.len == 0) return error.InvalidSnapshot;

        const separator = std.mem.lastIndexOfScalar(u8, pair, ':') orelse return error.InvalidSnapshot;
        if (separator == 0 or separator + 1 >= pair.len) return error.InvalidSnapshot;

        const raw_path = pair[0..separator];
        const raw_hash = pair[separator + 1 ..];
        const path_owned = try allocator.dupe(u8, raw_path);
        errdefer allocator.free(path_owned);

        try out.append(.{
            .path = try constrained_types.TrackedFilePath.init(path_owned),
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
        if (line.len == 0 or line[0] == '#' or line[0] == '!') continue;

        const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        if (!std.mem.eql(u8, line[0..eq_idx], key)) continue;
        return line[eq_idx + 1 ..];
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

fn loadTagNameList(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
) !StringList {
    var list = StringList.init(allocator);
    errdefer freeStringList(allocator, &list);

    var dir = persistence.dir.openDir(persistence.dataTagsPath(), .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return list,
        else => return err,
    };
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (std.mem.eql(u8, entry.name, ".trash")) continue;
        _ = constrained_types.TagName.init(entry.name) catch continue;
        try list.append(try allocator.dupe(u8, entry.name));
    }

    std.mem.sort([]u8, list.items, {}, isStringAscLessThan);
    return list;
}

fn isCommitIdDescLessThan(_: void, lhs: [64]u8, rhs: [64]u8) bool {
    return std.mem.order(u8, &lhs, &rhs) == .gt;
}

fn isFindCandidateDescLessThan(_: void, lhs: FindCandidate, rhs: FindCandidate) bool {
    if (lhs.created_at_millis != rhs.created_at_millis) return lhs.created_at_millis > rhs.created_at_millis;
    return std.mem.order(u8, lhs.parsed.commit_id.asSlice(), rhs.parsed.commit_id.asSlice()) == .gt;
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

fn isStringAscLessThan(_: void, lhs: []u8, rhs: []u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
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

    return try constrained_types.CommitId.init(parseHeadCommitId(bytes) orelse return error.InvalidHead);
}

fn parseHeadCommitId(bytes: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, bytes, '\n');
    while (iter.next()) |raw| {
        const line = std.mem.trim(u8, std.mem.trimRight(u8, raw, "\r"), " \t");
        if (line.len == 0 or line[0] == '#' or line[0] == '!') continue;
        if (std.mem.startsWith(u8, line, "commitId=")) return line["commitId=".len..];
        if (std.mem.indexOfScalar(u8, line, '=') != null) return null;
        return line;
    }
    return null;
}

fn loadHeadSnapshotEntries(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    persistence: PersistenceLayout,
) !?std.array_list.Managed(ContentEntry) {
    const head_id = try headCommitId(allocator, persistence) orelse return null;
    var details = try show(allocator, omohi_dir, head_id.asSlice());
    defer {
        allocator.free(details.message);
        allocator.free(details.created_at);
        freeTagList(allocator, &details.tags);
    }
    return details.entries;
}

fn findContentEntryByPath(
    entries: ?std.array_list.Managed(ContentEntry),
    absolute_path: []const u8,
) ?ContentEntry {
    if (entries) |list| {
        for (list.items) |entry| {
            if (std.mem.eql(u8, entry.path.asSlice(), absolute_path)) return entry;
        }
    }
    return null;
}

fn loadStagedEntriesOrEmpty(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
) !?local_staged.EntryList {
    return local_staged.loadStagedEntries(allocator, persistence) catch |err| switch (err) {
        error.MissingStagedEntries => null,
        else => return err,
    };
}

fn requireTrackedEntryByPath(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    absolute_path: []const u8,
) !TrackedEntry {
    var tracked = try loadTrackedOrEmpty(allocator, persistence);
    defer if (tracked) |*list| local_tracked.freeTrackedList(allocator, list);

    if (tracked) |list| {
        for (list.items) |entry| {
            if (std.mem.eql(u8, entry.path.asSlice(), absolute_path)) return entry;
        }
    }

    return error.TrackedFileNotFound;
}

fn headContentHashForPath(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    absolute_path: []const u8,
) !?constrained_types.ContentHash {
    const head_id = try headCommitId(allocator, persistence) orelse return null;
    var snapshot_entries = try readSnapshotEntriesForCommit(allocator, persistence, head_id.asSlice());
    defer freeContentEntryList(allocator, &snapshot_entries);

    for (snapshot_entries.items) |entry| {
        if (std.mem.eql(u8, entry.path.asSlice(), absolute_path)) return entry.content_hash;
    }
    return null;
}

fn readSnapshotEntriesForCommit(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    commit_id: []const u8,
) !std.array_list.Managed(ContentEntry) {
    const parsed = try readCommitFile(allocator, persistence, commit_id);
    defer freeParsedCommit(allocator, &parsed);
    return try readSnapshotEntries(allocator, persistence, parsed.snapshot_id.asSlice());
}

fn unstagePathIfPresent(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    staged_entries: ?local_staged.EntryList,
    absolute_path: []const u8,
) !void {
    if (staged_entries) |list| {
        if (local_staged.findByPath(list.items, absolute_path)) |entry| {
            try unstageEntry(allocator, persistence, staged_entries, entry);
        }
    }
}

fn unstageEntry(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    staged_entries: ?local_staged.EntryList,
    entry: StagedEntry,
) !void {
    const staged_file_id = local_staged.stagedFileIdForEntry(entry);
    try local_trash.moveStagedEntryToTrash(allocator, persistence, &staged_file_id);

    if (!hasOtherStagedEntryWithHash(staged_entries, entry.content_hash.asSlice(), entry.path.asSlice())) {
        local_trash.moveStagedObjectToTrash(allocator, persistence, entry.content_hash.asSlice()) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }
}

fn hasOtherStagedEntryWithHash(
    staged_entries: ?local_staged.EntryList,
    content_hash: []const u8,
    excluded_path: []const u8,
) bool {
    if (staged_entries) |list| {
        for (list.items) |entry| {
            if (std.mem.eql(u8, entry.path.asSlice(), excluded_path)) continue;
            if (std.mem.eql(u8, entry.content_hash.asSlice(), content_hash)) return true;
        }
    }
    return false;
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

fn ensureTrackTargetIsNotDirectory(absolute_path: []const u8) !void {
    var file = std.fs.openFileAbsolute(absolute_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        error.IsDir => return error.InvalidTrackedTarget,
        else => return err,
    };
    defer file.close();

    const stat = try file.stat();
    if (stat.kind == .directory) return error.InvalidTrackedTarget;
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

fn onlyFileNameInDir(dir: std.fs.Dir, path: []const u8, out: *[64]u8) !void {
    var target = try dir.openDir(path, .{ .iterate = true });
    defer target.close();

    var it = target.iterate();
    const first = (try it.next()) orelse return error.MissingFile;
    if (first.kind != .file) return error.InvalidEntry;
    if ((try it.next()) != null) return error.TooManyFiles;
    if (first.name.len != out.len) return error.InvalidHashLength;
    @memcpy(out, first.name);
}

fn filledHexId(ch: u8) [64]u8 {
    var value: [64]u8 = undefined;
    @memset(&value, ch);
    return value;
}

test "commitIdList returns commit ids in descending order" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    try initializeVersionForFirstTrack(allocator, omohi_dir);
    const tracked_path = try addTestFileForCommit(tmp.dir, allocator, "a.txt", "one");
    defer allocator.free(tracked_path);
    _ = try track(allocator, omohi_dir, tracked_path);
    try add(allocator, omohi_dir, tracked_path);
    const first = try commit(allocator, omohi_dir, "first");

    allocator.free(try addTestFileForCommit(tmp.dir, allocator, "a.txt", "two"));
    try add(allocator, omohi_dir, tracked_path);
    const newer = try commit(allocator, omohi_dir, "second");

    var ids = try commitIdList(allocator, omohi_dir);
    defer freeStringList(allocator, &ids);

    try std.testing.expect(ids.items.len >= 2);
    if (std.mem.order(u8, newer.asSlice(), first.asSlice()) == .gt) {
        try std.testing.expectEqualStrings(newer.asSlice(), ids.items[0]);
        try std.testing.expectEqualStrings(first.asSlice(), ids.items[1]);
    } else {
        try std.testing.expectEqualStrings(first.asSlice(), ids.items[0]);
        try std.testing.expectEqualStrings(newer.asSlice(), ids.items[1]);
    }
}

test "tagNameList returns tag names sorted ascending" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    const persistence = PersistenceLayout.init(omohi_dir);

    try omohi_dir.makePath(persistence.dataTagsPath());
    try local_tags.writeTag(allocator, persistence, "prod", "2026-03-27T00:00:00.000Z");
    try local_tags.writeTag(allocator, persistence, "alpha", "2026-03-27T00:00:01.000Z");

    var tags = try tagNameList(allocator, omohi_dir);
    defer freeStringList(allocator, &tags);

    try std.testing.expectEqual(@as(usize, 2), tags.items.len);
    try std.testing.expectEqualStrings("alpha", tags.items[0]);
    try std.testing.expectEqualStrings("prod", tags.items[1]);
}

test "stagedPathList returns staged paths sorted ascending" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    try initializeVersionForFirstTrack(allocator, omohi_dir);
    const b_path = try addTestFileForCommit(tmp.dir, allocator, "b.txt", "b");
    defer allocator.free(b_path);
    const a_path = try addTestFileForCommit(tmp.dir, allocator, "a.txt", "a");
    defer allocator.free(a_path);
    _ = try track(allocator, omohi_dir, b_path);
    _ = try track(allocator, omohi_dir, a_path);
    try add(allocator, omohi_dir, b_path);
    try add(allocator, omohi_dir, a_path);

    var paths = try stagedPathList(allocator, omohi_dir);
    defer freeStringList(allocator, &paths);

    try std.testing.expectEqual(@as(usize, 2), paths.items.len);
    try std.testing.expectEqualStrings(a_path, paths.items[0]);
    try std.testing.expectEqualStrings(b_path, paths.items[1]);
}

fn addTestFileForCommit(
    root: std.fs.Dir,
    allocator: std.mem.Allocator,
    name: []const u8,
    contents: []const u8,
) ![]u8 {
    var file = try root.createFile(name, .{ .truncate = true });
    defer file.close();
    try file.writeAll(contents);
    return try root.realpathAlloc(allocator, name);
}

fn writeFindFixtureCommit(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    commit_id: []const u8,
    message: []const u8,
    created_at: []const u8,
) !void {
    const persistence = PersistenceLayout.init(omohi_dir);
    const path = try persistence.commitsPath(allocator, commit_id);
    defer allocator.free(path);

    const snapshot_id = filledHexId('a');
    const content = try std.fmt.allocPrint(
        allocator,
        "snapshotId={s}\nmessage={s}\ncreatedAt={s}\n",
        .{ snapshot_id[0..], message, created_at },
    );
    defer allocator.free(content);

    const parent = std.fs.path.dirname(path) orelse return error.InvalidPath;
    try omohi_dir.makePath(parent);

    var file = try omohi_dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(content);
}

fn writeFindFixtureTags(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    commit_id: []const u8,
    tag_names: []const []const u8,
) !void {
    const persistence = PersistenceLayout.init(omohi_dir);
    try local_commit_tags.writeCommitTags(
        allocator,
        persistence,
        commit_id,
        tag_names,
        "2026-03-11T00:00:00.000Z",
        "2026-03-11T00:00:00.000Z",
    );
}

fn setCommitFailurePoint(point: CommitFailurePoint) void {
    if (!builtin.is_test) return;
    commit_failure_point = point;
}

fn clearCommitFailurePoint() void {
    if (!builtin.is_test) return;
    commit_failure_point = .none;
}

fn expectDirEmpty(dir: std.fs.Dir, path: []const u8) !void {
    var target = try dir.openDir(path, .{ .iterate = true });
    defer target.close();

    var it = target.iterate();
    try std.testing.expect((try it.next()) == null);
}

fn expectDirHasNoFiles(dir: std.fs.Dir, path: []const u8) !void {
    var target = try dir.openDir(path, .{ .iterate = true });
    defer target.close();

    var it = target.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file) return error.ExpectedNoFiles;
    }
}

fn writeCommitFixtureStage(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    path_suffix: []const u8,
    content_hash_ch: u8,
    payload: []const u8,
) !void {
    const persistence = PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.stagedEntriesPath());
    try omohi_dir.makePath(persistence.stagedObjectsPath());

    const content_hash = filledHexId(content_hash_ch);
    const entry_text = try std.fmt.allocPrint(
        allocator,
        "path=/tmp/{s}.txt\ntrackedFileId=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\ncontentHash={s}\n",
        .{ path_suffix, content_hash[0..] },
    );
    defer allocator.free(entry_text);

    const entry_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.stagedEntriesPath(), path_suffix });
    defer allocator.free(entry_path);
    var entry_file = try omohi_dir.createFile(entry_path, .{});
    defer entry_file.close();
    try entry_file.writeAll(entry_text);

    const object_path = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}",
        .{ persistence.stagedObjectsPath(), content_hash[0..] },
    );
    defer allocator.free(object_path);
    var object_file = try omohi_dir.createFile(object_path, .{});
    defer object_file.close();
    try object_file.writeAll(payload);
}

test "propertyValue ignores java properties comment lines" {
    const bytes =
        "#Tue Mar 10 16:00:00 UTC 2026\n" ++
        "!generated by java.util.Properties\n" ++
        "entries=/objects/aa/hash:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n";
    const actual = propertyValue(bytes, "entries");
    try std.testing.expect(actual != null);
    try std.testing.expectEqualStrings(
        "/objects/aa/hash:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        actual.?,
    );
}

test "parseHeadCommitId supports plain id and rejects unrelated key-value" {
    const plain = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n";
    const plain_id = parseHeadCommitId(plain);
    try std.testing.expect(plain_id != null);
    try std.testing.expectEqualStrings(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        plain_id.?,
    );

    try std.testing.expect(parseHeadCommitId("snapshotId=abc\n") == null);
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

test "track rejects directory targets" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, ".");
    defer allocator.free(absolute_path);

    try std.testing.expectError(error.InvalidTrackedTarget, track(allocator, omohi_dir, absolute_path));
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

test "initializeVersionForFirstTrack writes VERSION for empty store" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    try initializeVersionForFirstTrack(allocator, omohi_dir);

    const persistence = PersistenceLayout.init(omohi_dir);
    const actual = try local_version.readVersion(allocator, persistence);
    try std.testing.expectEqual(version_guard.expected_store_version, actual);
}

test "initializeVersionForFirstTrack rejects non-empty store without VERSION" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var marker = try omohi_dir.createFile("HEAD", .{});
    defer marker.close();
    try marker.writeAll("dummy\n");

    try std.testing.expectError(
        error.MissingStoreVersion,
        initializeVersionForFirstTrack(allocator, omohi_dir),
    );
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

test "add requires tracked absolute path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var source_file = try source_dir.createFile("untracked.txt", .{});
    try source_file.writeAll("payload");
    source_file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, "untracked.txt");
    defer allocator.free(absolute_path);

    try std.testing.expectError(error.TrackedFileNotFound, add(allocator, omohi_dir, absolute_path));
}

test "rm distinguishes tracked-not-found and staged-not-found" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var source_file = try source_dir.createFile("memo.txt", .{});
    try source_file.writeAll("payload");
    source_file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, "memo.txt");
    defer allocator.free(absolute_path);

    try std.testing.expectError(error.TrackedFileNotFound, rm(allocator, omohi_dir, absolute_path));
    _ = try track(allocator, omohi_dir, absolute_path);
    try std.testing.expectError(error.StagedFileNotFound, rm(allocator, omohi_dir, absolute_path));
}

test "add uses absolute path when generating staged file id" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var source_file = try source_dir.createFile("memo.txt", .{});
    try source_file.writeAll("hello add");
    source_file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, "memo.txt");
    defer allocator.free(absolute_path);
    _ = try track(allocator, omohi_dir, absolute_path);
    try add(allocator, omohi_dir, absolute_path);

    const content_hash = try contentHashFromFile(allocator, source_dir, "memo.txt");
    const staged_file_id = hash.stagedFileIdFrom(absolute_path, &content_hash);

    var staged_entry_id: [64]u8 = undefined;
    try onlyFileNameInDir(omohi_dir, "staged/entries", &staged_entry_id);
    try std.testing.expectEqualSlices(u8, staged_file_id[0..], staged_entry_id[0..]);

    const stored_path = try std.fmt.allocPrint(allocator, "staged/entries/{s}", .{staged_file_id[0..]});
    defer allocator.free(stored_path);
    const stored = try omohi_dir.readFileAlloc(allocator, stored_path, 1024);
    defer allocator.free(stored);
    try std.testing.expect(std.mem.indexOf(u8, stored, "path=") != null);
    try std.testing.expect(std.mem.indexOf(u8, stored, "trackedFileId=") != null);
}

test "add does not stage file when content matches HEAD" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try initializeVersionForFirstTrack(allocator, omohi_dir);

    var source_file = try source_dir.createFile("memo.txt", .{});
    try source_file.writeAll("hello add");
    source_file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, "memo.txt");
    defer allocator.free(absolute_path);
    _ = try track(allocator, omohi_dir, absolute_path);

    try add(allocator, omohi_dir, absolute_path);
    _ = try commit(allocator, omohi_dir, "first");
    try add(allocator, omohi_dir, absolute_path);

    try expectDirHasNoFiles(omohi_dir, "staged/entries");
    try expectDirHasNoFiles(omohi_dir, "staged/objects");
}

test "add removes staged entry when file returns to HEAD content" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try initializeVersionForFirstTrack(allocator, omohi_dir);

    var source_file = try source_dir.createFile("memo.txt", .{});
    try source_file.writeAll("before");
    source_file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, "memo.txt");
    defer allocator.free(absolute_path);
    _ = try track(allocator, omohi_dir, absolute_path);
    try add(allocator, omohi_dir, absolute_path);
    _ = try commit(allocator, omohi_dir, "first");

    source_file = try source_dir.createFile("memo.txt", .{ .truncate = true });
    try source_file.writeAll("after");
    source_file.close();
    try add(allocator, omohi_dir, absolute_path);

    source_file = try source_dir.createFile("memo.txt", .{ .truncate = true });
    try source_file.writeAll("before");
    source_file.close();
    try add(allocator, omohi_dir, absolute_path);

    try expectDirHasNoFiles(omohi_dir, "staged/entries");
    try expectDirHasNoFiles(omohi_dir, "staged/objects");
}

test "status tolerates invalid tracked directory entry" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    const persistence = PersistenceLayout.init(omohi_dir);

    try omohi_dir.makePath(persistence.trackedPath());
    try omohi_dir.makePath(persistence.trackedTrashPath());

    const directory_path = try source_dir.realpathAlloc(allocator, ".");
    defer allocator.free(directory_path);

    var tracked_id: [32]u8 = undefined;
    @memset(&tracked_id, 'd');
    try local_tracked.writeTracked(allocator, persistence, &tracked_id, directory_path);

    var statuses = try status(allocator, omohi_dir);
    defer freeStatusList(allocator, &statuses);

    try std.testing.expectEqual(@as(usize, 1), statuses.items.len);
    try std.testing.expectEqual(.tracked, statuses.items[0].status);
    try std.testing.expectEqualStrings(directory_path, statuses.items[0].path);
}

test "find sorts by createdAt desc and limits to ten commits" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const id_chars = [_]u8{ 'f', 'e', 'd', 'c', 'b', 'a', '9', '8', '7', '6', '0' };
    for (id_chars, 0..) |id_ch, idx| {
        const commit_id = filledHexId(id_ch);
        const created_at = try std.fmt.allocPrint(
            allocator,
            "2026-03-{d:0>2}T00:00:00.000Z",
            .{idx + 1},
        );
        defer allocator.free(created_at);
        const message = try std.fmt.allocPrint(allocator, "msg-{d}", .{idx + 1});
        defer allocator.free(message);

        try writeFindFixtureCommit(allocator, omohi_dir, commit_id[0..], message, created_at);
    }

    var list = try find(allocator, omohi_dir, null, null);
    defer freeCommitSummaryList(allocator, &list);

    try std.testing.expectEqual(@as(usize, 10), list.items.len);
    try std.testing.expectEqualStrings("msg-11", list.items[0].message);
    try std.testing.expectEqualStrings("msg-2", list.items[9].message);
    try std.testing.expectEqualSlices(u8, filledHexId('0')[0..], list.items[0].commit_id.asSlice());
}

test "find applies tag and date filters as intersection" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const commit_a = filledHexId('a');
    const commit_b = filledHexId('b');

    try writeFindFixtureCommit(allocator, omohi_dir, commit_a[0..], "release-a", "2026-03-10T18:00:00.000Z");
    try writeFindFixtureCommit(allocator, omohi_dir, commit_b[0..], "prod-b", "2026-03-07T01:00:00.000Z");

    const release_tags = [_][]const u8{"release"};
    const prod_tags = [_][]const u8{"prod"};
    try writeFindFixtureTags(allocator, omohi_dir, commit_a[0..], &release_tags);
    try writeFindFixtureTags(allocator, omohi_dir, commit_b[0..], &prod_tags);

    var by_tag = try find(allocator, omohi_dir, "release", null);
    defer freeCommitSummaryList(allocator, &by_tag);
    try std.testing.expectEqual(@as(usize, 1), by_tag.items.len);
    try std.testing.expectEqualStrings("release-a", by_tag.items[0].message);

    const date_a = try local_date.utcIso8601ToLocalYmd("2026-03-10T18:00:00.000Z");
    var by_date = try find(allocator, omohi_dir, null, date_a[0..]);
    defer freeCommitSummaryList(allocator, &by_date);
    try std.testing.expectEqual(@as(usize, 1), by_date.items.len);
    try std.testing.expectEqualStrings("release-a", by_date.items[0].message);

    var by_tag_and_date = try find(allocator, omohi_dir, "release", date_a[0..]);
    defer freeCommitSummaryList(allocator, &by_tag_and_date);
    try std.testing.expectEqual(@as(usize, 1), by_tag_and_date.items.len);
    try std.testing.expectEqualStrings("release-a", by_tag_and_date.items[0].message);

    var no_intersection = try find(allocator, omohi_dir, "prod", date_a[0..]);
    defer freeCommitSummaryList(allocator, &no_intersection);
    try std.testing.expectEqual(@as(usize, 0), no_intersection.items.len);
}

test "tagList returns CommitNotFound when commit does not exist" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const missing_commit = filledHexId('a');
    try std.testing.expectError(error.CommitNotFound, tagList(allocator, omohi_dir, missing_commit[0..]));
}

test "show returns CommitNotFound when commit does not exist" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const missing_commit = filledHexId('c');
    try std.testing.expectError(error.CommitNotFound, show(allocator, omohi_dir, missing_commit[0..]));
}

test "tagList returns empty when commit exists and has no tags" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const existing_commit = filledHexId('b');
    try writeFindFixtureCommit(
        allocator,
        omohi_dir,
        existing_commit[0..],
        "fixture-message",
        "2026-03-12T00:00:00.000Z",
    );

    var tags = try tagList(allocator, omohi_dir, existing_commit[0..]);
    defer freeTagList(allocator, &tags);
    try std.testing.expectEqual(@as(usize, 0), tags.items.len);
}

test "appendJournal writes one line into UTC daily file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    try appendJournal(allocator, omohi_dir, "track", "{\"path\":\"/tmp/sample\"}");

    var journal_dir = try omohi_dir.openDir("journal", .{ .iterate = true });
    defer journal_dir.close();

    var it = journal_dir.iterate();
    const entry = (try it.next()) orelse return error.ExpectedJournalFile;
    try std.testing.expectEqual(std.fs.File.Kind.file, entry.kind);

    const journal_path = try std.fmt.allocPrint(allocator, "journal/{s}", .{entry.name});
    defer allocator.free(journal_path);
    const bytes = try omohi_dir.readFileAlloc(allocator, journal_path, 4096);
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, " track 1 ") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "{\"path\":\"/tmp/sample\"}") != null);
}

test "journal returns latest lines in reverse chronological order" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    try appendJournal(allocator, omohi_dir, "track", "{\"path\":\"/tmp/one\"}");
    std.Thread.sleep(1_000_000);
    try appendJournal(allocator, omohi_dir, "add", "{\"path\":\"/tmp/two\"}");

    var lines = try journal(allocator, omohi_dir, 2);
    defer freeStringList(allocator, &lines);

    try std.testing.expectEqual(@as(usize, 2), lines.items.len);
    try std.testing.expect(std.mem.indexOf(u8, lines.items[0], "\"/tmp/two\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, lines.items[1], "\"/tmp/one\"") != null);
}

test "commit rejects staged entry when corresponding object is missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try initializeVersionForFirstTrack(allocator, omohi_dir);

    try writeCommitFixtureStage(allocator, omohi_dir, "dangling-entry", 'a', "payload");
    try omohi_dir.deleteFile("staged/objects/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");

    try std.testing.expectError(error.StagedObjectMissing, commit(allocator, omohi_dir, "msg"));
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("LOCK", .{}));
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("HEAD", .{}));
}

test "commit releases lock and keeps retryable state when failing before HEAD write" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try initializeVersionForFirstTrack(allocator, omohi_dir);
    try writeCommitFixtureStage(allocator, omohi_dir, "retry-entry", 'b', "payload");

    setCommitFailurePoint(.before_write_head);
    defer clearCommitFailurePoint();

    try std.testing.expectError(error.TestInjectedFailure, commit(allocator, omohi_dir, "msg"));
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("LOCK", .{}));
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("HEAD", .{}));

    const object_path = "objects/bb/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const stored_object = try omohi_dir.readFileAlloc(allocator, object_path, 1024);
    defer allocator.free(stored_object);
    try std.testing.expectEqualStrings("payload", stored_object);

    clearCommitFailurePoint();

    _ = try commit(allocator, omohi_dir, "msg");

    const head_bytes = try omohi_dir.readFileAlloc(allocator, "HEAD", 256);
    defer allocator.free(head_bytes);
    try std.testing.expect(parseHeadCommitId(head_bytes) != null);
    try expectDirEmpty(omohi_dir, "staged/entries");
    try expectDirEmpty(omohi_dir, "staged/objects");
}

test "commit can recover after failure between HEAD write and staged reset" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try initializeVersionForFirstTrack(allocator, omohi_dir);
    try writeCommitFixtureStage(allocator, omohi_dir, "recover-entry", 'c', "payload");

    setCommitFailurePoint(.before_reset_staged);
    defer clearCommitFailurePoint();

    try std.testing.expectError(error.TestInjectedFailure, commit(allocator, omohi_dir, "msg"));
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("LOCK", .{}));

    const head_bytes_before_retry = try omohi_dir.readFileAlloc(allocator, "HEAD", 256);
    defer allocator.free(head_bytes_before_retry);
    const head_before_retry = parseHeadCommitId(head_bytes_before_retry) orelse return error.InvalidHead;
    try std.testing.expectEqual(@as(usize, 64), head_before_retry.len);

    clearCommitFailurePoint();

    const retried_commit_id = try commit(allocator, omohi_dir, "msg");
    try std.testing.expectEqualSlices(u8, head_before_retry, retried_commit_id.asSlice());

    const head_bytes_after_retry = try omohi_dir.readFileAlloc(allocator, "HEAD", 256);
    defer allocator.free(head_bytes_after_retry);
    const head_after_retry = parseHeadCommitId(head_bytes_after_retry) orelse return error.InvalidHead;
    try std.testing.expectEqualSlices(u8, retried_commit_id.asSlice(), head_after_retry);
    try expectDirEmpty(omohi_dir, "staged/entries");
    try expectDirEmpty(omohi_dir, "staged/objects");
}
