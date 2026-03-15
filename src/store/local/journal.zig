const std = @import("std");

const atomic_write = @import("../storage/atomic_write.zig");
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
