const std = @import("std");

const atomic_write = @import("../storage/atomic_write.zig");
const StringList = @import("../object/api_types.zig").StringList;
const PersistenceLayout = @import("../object/persistence_layout.zig").PersistenceLayout;

const max_journal_file_size = 64 * 1024 * 1024;
const journal_format_version: u32 = 1;

pub const JournalRecord = struct {
    ts_utc: [24]u8,
    local_ts: [29]u8,
    command_type: []const u8,
    payload_json: []const u8,
};

/// Appends one journal record into daily UTC journal file.
pub fn appendRecord(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    record: JournalRecord,
) !void {
    if (!isSupportedCommandType(record.command_type)) return error.InvalidJournalCommandType;

    const path = try journalDailyPath(allocator, persistence, record.ts_utc[0..10]);
    defer allocator.free(path);

    const line = try std.fmt.allocPrint(
        allocator,
        "{s} {s} {s} {d} {s}\n",
        .{ record.ts_utc, record.local_ts, record.command_type, journal_format_version, record.payload_json },
    );
    defer allocator.free(line);

    const existing = persistence.dir.readFileAlloc(allocator, path, max_journal_file_size) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (existing) |bytes| allocator.free(bytes);

    if (existing) |bytes| {
        const next = try std.fmt.allocPrint(allocator, "{s}{s}", .{ bytes, line });
        defer allocator.free(next);
        try atomic_write.atomicWrite(allocator, persistence.dir, path, next);
        return;
    }

    try atomic_write.atomicWrite(allocator, persistence.dir, path, line);
}

/// Loads latest journal lines in reverse chronological order.
pub fn readLatestLines(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    limit: usize,
) !StringList {
    var out = StringList.init(allocator);
    errdefer freeStringList(allocator, &out);

    if (limit == 0) return out;

    var journal_dir = persistence.dir.openDir(persistence.journalPath(), .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return out,
        else => return err,
    };
    defer journal_dir.close();

    var names = StringList.init(allocator);
    defer freeStringList(allocator, &names);

    var it = journal_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".log")) continue;
        try names.append(try allocator.dupe(u8, entry.name));
    }

    std.mem.sort([]u8, names.items, {}, isNameDescLessThan);

    for (names.items) |name| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.journalPath(), name });
        defer allocator.free(path);

        const bytes = try persistence.dir.readFileAlloc(allocator, path, max_journal_file_size);
        defer allocator.free(bytes);

        try appendLatestLinesFromBytes(allocator, &out, bytes, limit);
        if (out.items.len >= limit) break;
    }

    return out;
}

pub fn freeStringList(allocator: std.mem.Allocator, list: *StringList) void {
    for (list.items) |item| allocator.free(item);
    list.deinit();
}

fn isSupportedCommandType(command_type: []const u8) bool {
    return std.mem.eql(u8, command_type, "track") or
        std.mem.eql(u8, command_type, "untrack") or
        std.mem.eql(u8, command_type, "add") or
        std.mem.eql(u8, command_type, "rm") or
        std.mem.eql(u8, command_type, "commit") or
        std.mem.eql(u8, command_type, "tag-add") or
        std.mem.eql(u8, command_type, "tag-rm");
}

fn journalDailyPath(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    utc_ymd: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}.log", .{
        persistence.journalPath(),
        utc_ymd,
    });
}

fn isNameDescLessThan(_: void, lhs: []u8, rhs: []u8) bool {
    return std.mem.order(u8, lhs, rhs) == .gt;
}

fn appendLatestLinesFromBytes(
    allocator: std.mem.Allocator,
    out: *StringList,
    bytes: []const u8,
    limit: usize,
) !void {
    var end = bytes.len;
    while (end > 0 and out.items.len < limit) {
        var line_end = end;
        if (bytes[line_end - 1] == '\n') line_end -= 1;

        var start = line_end;
        while (start > 0 and bytes[start - 1] != '\n') : (start -= 1) {}

        if (line_end > start) {
            try out.append(try allocator.dupe(u8, bytes[start..line_end]));
        }

        if (start == 0) break;
        end = start;
    }
}

test "appendRecord creates and appends daily journal file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const persistence = PersistenceLayout.init(omohi_dir);

    try appendRecord(allocator, persistence, .{
        .ts_utc = "2026-03-15T00:00:00.000Z".*,
        .local_ts = "2026-03-15T09:00:00.000+09:00".*,
        .command_type = "track",
        .payload_json = "{\"path\":\"/tmp/a\"}",
    });

    try appendRecord(allocator, persistence, .{
        .ts_utc = "2026-03-15T00:00:01.000Z".*,
        .local_ts = "2026-03-15T09:00:01.000+09:00".*,
        .command_type = "add",
        .payload_json = "{\"path\":\"/tmp/a\"}",
    });

    const bytes = try omohi_dir.readFileAlloc(allocator, "journal/2026-03-15.log", 4096);
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "2026-03-15T00:00:00.000Z") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "2026-03-15T00:00:01.000Z") != null);
}

test "appendRecord rejects unsupported command type" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const persistence = PersistenceLayout.init(omohi_dir);
    try std.testing.expectError(error.InvalidJournalCommandType, appendRecord(allocator, persistence, .{
        .ts_utc = "2026-03-15T00:00:00.000Z".*,
        .local_ts = "2026-03-15T09:00:00.000+09:00".*,
        .command_type = "status",
        .payload_json = "{}",
    }));
}

test "readLatestLines returns newest records across files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const persistence = PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.journalPath());

    try atomic_write.atomicWrite(
        allocator,
        omohi_dir,
        "journal/2026-03-14.log",
        "2026-03-14T00:00:00.000Z old-a track 1 {}\n2026-03-14T00:00:01.000Z old-b add 1 {}\n",
    );
    try atomic_write.atomicWrite(
        allocator,
        omohi_dir,
        "journal/2026-03-15.log",
        "2026-03-15T00:00:00.000Z new-a track 1 {}\n2026-03-15T00:00:01.000Z new-b add 1 {}\n",
    );

    var lines = try readLatestLines(allocator, persistence, 3);
    defer freeStringList(allocator, &lines);

    try std.testing.expectEqual(@as(usize, 3), lines.items.len);
    try std.testing.expectEqualStrings("2026-03-15T00:00:01.000Z new-b add 1 {}", lines.items[0]);
    try std.testing.expectEqualStrings("2026-03-15T00:00:00.000Z new-a track 1 {}", lines.items[1]);
    try std.testing.expectEqualStrings("2026-03-14T00:00:01.000Z old-b add 1 {}", lines.items[2]);
}

test "readLatestLines returns empty when journal directory is missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const persistence = PersistenceLayout.init(omohi_dir);
    var lines = try readLatestLines(allocator, persistence, 20);
    defer freeStringList(allocator, &lines);

    try std.testing.expectEqual(@as(usize, 0), lines.items.len);
}
