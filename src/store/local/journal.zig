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

pub const JournalEntry = struct {
    local_ts: []u8,
    command_type: []u8,
    payload_json: []u8,

    /// Releases the owned fields of one journal entry.
    pub fn deinit(self: *JournalEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.local_ts);
        allocator.free(self.command_type);
        allocator.free(self.payload_json);
    }
};

pub const JournalEntryList = std.array_list.Managed(JournalEntry);

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

/// Loads latest journal entries in reverse chronological order.
pub fn readLatestEntries(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    limit: usize,
) !JournalEntryList {
    var out = JournalEntryList.init(allocator);
    errdefer freeEntryList(allocator, &out);

    if (limit == 0) return out;

    var journal_dir = persistence.dir.openDir(persistence.journalPath(), .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return out,
        else => return err,
    };
    defer journal_dir.close();

    var names = std.array_list.Managed([]u8).init(allocator);
    defer freeNameList(allocator, &names);

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

        try appendLatestEntriesFromBytes(allocator, &out, bytes, limit);
        if (out.items.len >= limit) break;
    }

    return out;
}

// Releases the owned journal entries stored in the list.
pub fn freeEntryList(allocator: std.mem.Allocator, list: *JournalEntryList) void {
    for (list.items) |*item| item.deinit(allocator);
    list.deinit();
}

// Restricts journal persistence to the supported mutating command types.
fn isSupportedCommandType(command_type: []const u8) bool {
    return std.mem.eql(u8, command_type, "track") or
        std.mem.eql(u8, command_type, "untrack") or
        std.mem.eql(u8, command_type, "add") or
        std.mem.eql(u8, command_type, "rm") or
        std.mem.eql(u8, command_type, "commit") or
        std.mem.eql(u8, command_type, "tag-add") or
        std.mem.eql(u8, command_type, "tag-rm");
}

// Builds the owned daily journal path for one UTC date.
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

// Sorts journal file names in descending order so newer days are read first.
fn isNameDescLessThan(_: void, lhs: []u8, rhs: []u8) bool {
    return std.mem.order(u8, lhs, rhs) == .gt;
}

// Releases the owned journal file names stored in the list.
fn freeNameList(allocator: std.mem.Allocator, list: *std.array_list.Managed([]u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit();
}

// Appends newest journal entries from one file into the output list until the limit is reached.
fn appendLatestEntriesFromBytes(
    allocator: std.mem.Allocator,
    out: *JournalEntryList,
    bytes: []const u8,
    limit: usize,
) !void {
    var end = bytes.len;
    while (end > 0 and out.items.len < limit) {
        var line_end = end;
        if (bytes[line_end - 1] == '\n') line_end -= 1;

        var start = line_end;
        while (start > 0 and bytes[start - 1] != '\n') : (start -= 1) {}

        if (line_end > start) try out.append(try parseLineOwned(allocator, bytes[start..line_end]));

        if (start == 0) break;
        end = start;
    }
}

// Parses one persisted journal line into an owned entry for CLI-facing presentation.
fn parseLineOwned(allocator: std.mem.Allocator, line: []const u8) !JournalEntry {
    const first_space = std.mem.indexOfScalar(u8, line, ' ') orelse return error.InvalidJournalRecord;
    const second_space = std.mem.indexOfScalarPos(u8, line, first_space + 1, ' ') orelse return error.InvalidJournalRecord;
    const third_space = std.mem.indexOfScalarPos(u8, line, second_space + 1, ' ') orelse return error.InvalidJournalRecord;
    const fourth_space = std.mem.indexOfScalarPos(u8, line, third_space + 1, ' ') orelse return error.InvalidJournalRecord;

    if (fourth_space + 1 > line.len) return error.InvalidJournalRecord;

    const version_text = line[third_space + 1 .. fourth_space];
    if (version_text.len == 0) return error.InvalidJournalRecord;
    const version = std.fmt.parseInt(u32, version_text, 10) catch return error.InvalidJournalRecord;
    if (version != journal_format_version) return error.InvalidJournalRecord;

    const local_ts = line[first_space + 1 .. second_space];
    const command_type = line[second_space + 1 .. third_space];
    const payload_json = line[fourth_space + 1 ..];

    const local_ts_owned = try allocator.dupe(u8, local_ts);
    errdefer allocator.free(local_ts_owned);
    const command_type_owned = try allocator.dupe(u8, command_type);
    errdefer allocator.free(command_type_owned);
    const payload_json_owned = try allocator.dupe(u8, payload_json);

    return .{
        .local_ts = local_ts_owned,
        .command_type = command_type_owned,
        .payload_json = payload_json_owned,
    };
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

test "parseLineOwned extracts local timestamp, command type, and payload" {
    const entry = try parseLineOwned(
        std.testing.allocator,
        "2026-03-15T00:00:01.000Z 2026-03-15T09:00:01.000+09:00 add 1 {\"message\":\"hello world\"}",
    );
    defer {
        var mutable_entry = entry;
        mutable_entry.deinit(std.testing.allocator);
    }

    try std.testing.expectEqualStrings("2026-03-15T09:00:01.000+09:00", entry.local_ts);
    try std.testing.expectEqualStrings("add", entry.command_type);
    try std.testing.expectEqualStrings("{\"message\":\"hello world\"}", entry.payload_json);
}

test "readLatestEntries returns newest records across files" {
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
        "2026-03-14T00:00:00.000Z 2026-03-14T09:00:00.000+09:00 track 1 {}\n" ++
            "2026-03-14T00:00:01.000Z 2026-03-14T09:00:01.000+09:00 add 1 {}\n",
    );
    try atomic_write.atomicWrite(
        allocator,
        omohi_dir,
        "journal/2026-03-15.log",
        "2026-03-15T00:00:00.000Z 2026-03-15T09:00:00.000+09:00 track 1 {}\n" ++
            "2026-03-15T00:00:01.000Z 2026-03-15T09:00:01.000+09:00 add 1 {}\n",
    );

    var lines = try readLatestEntries(allocator, persistence, 3);
    defer freeEntryList(allocator, &lines);

    try std.testing.expectEqual(@as(usize, 3), lines.items.len);
    try std.testing.expectEqualStrings("2026-03-15T09:00:01.000+09:00", lines.items[0].local_ts);
    try std.testing.expectEqualStrings("add", lines.items[0].command_type);
    try std.testing.expectEqualStrings("{}", lines.items[0].payload_json);
    try std.testing.expectEqualStrings("2026-03-15T09:00:00.000+09:00", lines.items[1].local_ts);
    try std.testing.expectEqualStrings("track", lines.items[1].command_type);
    try std.testing.expectEqualStrings("2026-03-14T09:00:01.000+09:00", lines.items[2].local_ts);
}

test "readLatestEntries returns empty when journal directory is missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const persistence = PersistenceLayout.init(omohi_dir);
    var lines = try readLatestEntries(allocator, persistence, 20);
    defer freeEntryList(allocator, &lines);

    try std.testing.expectEqual(@as(usize, 0), lines.items.len);
}
