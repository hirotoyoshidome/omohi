const std = @import("std");

const atomic_write = @import("../atomic_write.zig");
const trash = @import("./trash.zig");
const PersistenceLayout = @import("../../object/persistence_layout.zig").PersistenceLayout;
const constrained_types = @import("../../object/constrained_types.zig");

pub const TagStringList = std.array_list.Managed([]u8);

pub const CommitTagsRecord = struct {
    commit_id: constrained_types.CommitId,
    tags: TagStringList,
    created_at: []u8,
    updated_at: []u8,

    pub fn deinit(self: *CommitTagsRecord, allocator: std.mem.Allocator) void {
        for (self.tags.items) |tag| allocator.free(tag);
        self.tags.deinit();
        allocator.free(self.created_at);
        allocator.free(self.updated_at);
    }
};

const max_commit_tags_file_size = 32 * 1024;

pub fn writeCommitTags(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    commit_id: []const u8,
    tags: []const []const u8,
    created_at: []const u8,
    updated_at: []const u8,
) !void {
    _ = try constrained_types.CommitId.init(commit_id);
    for (tags) |tag_name| try validateTagFileName(tag_name);

    const content = try formatCommitTagsFile(allocator, commit_id, tags, created_at, updated_at);
    defer allocator.free(content);

    const path = try persistence.commitTagsPath(allocator, commit_id);
    defer allocator.free(path);

    try atomic_write.atomicWrite(allocator, persistence.dir, path, content);
}

pub fn readCommitTags(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    commit_id: []const u8,
) !CommitTagsRecord {
    _ = try constrained_types.CommitId.init(commit_id);

    const path = try persistence.commitTagsPath(allocator, commit_id);
    defer allocator.free(path);

    const bytes = try persistence.dir.readFileAlloc(allocator, path, max_commit_tags_file_size);
    defer allocator.free(bytes);
    return parseCommitTagsFile(allocator, bytes);
}

pub fn deleteCommitTags(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    commit_id: []const u8,
) !void {
    try trash.moveCommitTagsToTrash(allocator, persistence, commit_id);
}

fn formatCommitTagsFile(
    allocator: std.mem.Allocator,
    commit_id: []const u8,
    tags: []const []const u8,
    created_at: []const u8,
    updated_at: []const u8,
) ![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();
    var writer = buf.writer();
    try writer.print("commitId={s}\n", .{commit_id});
    try writer.print("tags.count={d}\n", .{tags.len});
    for (tags, 0..) |tag_name, idx| {
        try writer.print("tag.{d}={s}\n", .{ idx, tag_name });
    }
    try writer.print("createdAt={s}\n", .{created_at});
    try writer.print("updatedAt={s}\n", .{updated_at});
    return buf.toOwnedSlice();
}

fn parseCommitTagsFile(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !CommitTagsRecord {
    var commit_value: ?[]const u8 = null;
    var created_value: ?[]const u8 = null;
    var updated_value: ?[]const u8 = null;
    var tags_count: ?usize = null;
    var tags = TagStringList.init(allocator);
    errdefer {
        for (tags.items) |tag| allocator.free(tag);
        tags.deinit();
    }

    var iter = std.mem.splitScalar(u8, bytes, '\n');
    while (iter.next()) |line_raw| {
        const line = std.mem.trim(u8, std.mem.trimRight(u8, line_raw, "\r"), " \t");
        if (line.len == 0 or line[0] == '#') continue;

        if (std.mem.startsWith(u8, line, "commitId=")) {
            commit_value = line["commitId=".len..];
            continue;
        }
        if (std.mem.startsWith(u8, line, "tags.count=")) {
            tags_count = try std.fmt.parseInt(usize, line["tags.count=".len..], 10);
            continue;
        }
        if (std.mem.startsWith(u8, line, "createdAt=")) {
            created_value = line["createdAt=".len..];
            continue;
        }
        if (std.mem.startsWith(u8, line, "updatedAt=")) {
            updated_value = line["updatedAt=".len..];
            continue;
        }
        if (std.mem.startsWith(u8, line, "tag.")) {
            const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse return error.InvalidCommitTags;
            const key = line[0..eq_idx];
            if (!std.mem.startsWith(u8, key, "tag.")) return error.InvalidCommitTags;
            const index_part = key["tag.".len..];
            _ = try std.fmt.parseInt(usize, index_part, 10);
            const tag_value = line[eq_idx + 1 ..];
            try validateTagFileName(tag_value);
            try tags.append(try allocator.dupe(u8, tag_value));
            continue;
        }
    }

    const parsed_commit_id = try constrained_types.CommitId.init(commit_value orelse return error.InvalidCommitTags);
    const created_at = try allocator.dupe(u8, created_value orelse return error.InvalidCommitTags);
    errdefer allocator.free(created_at);
    const updated_at = try allocator.dupe(u8, updated_value orelse return error.InvalidCommitTags);
    errdefer allocator.free(updated_at);

    if (tags_count) |expected_count| {
        if (expected_count != tags.items.len) return error.InvalidCommitTags;
    } else {
        return error.InvalidCommitTags;
    }

    return .{
        .commit_id = parsed_commit_id,
        .tags = tags,
        .created_at = created_at,
        .updated_at = updated_at,
    };
}

fn validateTagFileName(tag_name: []const u8) !void {
    _ = try constrained_types.TagName.init(tag_name);
    if (std.mem.indexOfScalar(u8, tag_name, '/')) |_| return error.InvalidTagName;
    if (std.mem.indexOf(u8, tag_name, "..")) |_| return error.InvalidTagName;
}

test "writeCommitTags and readCommitTags round-trip record" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    const persistence = PersistenceLayout.init(omohi_dir);

    var commit_id: [64]u8 = undefined;
    @memset(&commit_id, 'd');
    const tag_names = [_][]const u8{ "release", "mobile" };

    try writeCommitTags(
        allocator,
        persistence,
        &commit_id,
        &tag_names,
        "2026-02-24T02:00:00.000Z",
        "2026-02-24T03:00:00.000Z",
    );

    var record = try readCommitTags(allocator, persistence, &commit_id);
    defer record.deinit(allocator);

    try std.testing.expectEqualSlices(u8, &commit_id, record.commit_id.asSlice());
    try std.testing.expectEqual(@as(usize, 2), record.tags.items.len);
    try std.testing.expectEqualStrings("release", record.tags.items[0]);
    try std.testing.expectEqualStrings("mobile", record.tags.items[1]);
    try std.testing.expectEqualStrings("2026-02-24T02:00:00.000Z", record.created_at);
    try std.testing.expectEqualStrings("2026-02-24T03:00:00.000Z", record.updated_at);
}

test "deleteCommitTags moves file into prefixed trash" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    var persistence = PersistenceLayout.init(omohi_dir);

    var commit_id: [64]u8 = undefined;
    @memset(&commit_id, 'e');
    const tag_names = [_][]const u8{"prod"};
    try writeCommitTags(
        allocator,
        persistence,
        &commit_id,
        &tag_names,
        "2026-02-24T04:00:00.000Z",
        "2026-02-24T04:00:00.000Z",
    );

    try deleteCommitTags(allocator, persistence, &commit_id);

    const live = try persistence.commitTagsPath(allocator, &commit_id);
    defer allocator.free(live);
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile(live, .{}));

    const trashed = try persistence.commitTagsTrashPath(allocator, &commit_id);
    defer allocator.free(trashed);
    const bytes = try omohi_dir.readFileAlloc(allocator, trashed, 1024);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "tags.count=1") != null);
}
