const std = @import("std");
const store_api = @import("../../store/api.zig");

/// Appends a successful command event to the journal.
pub fn appendJournal(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    command_type: []const u8,
    payload_json: []const u8,
) !void {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    try store_api.appendJournal(allocator, omohi_dir, command_type, payload_json);
}

test "appendJournal delegates to store and writes journal file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);
    try appendJournal(allocator, omohi_dir, "track", "{\"path\":\"/tmp/ops\"}");

    var journal_dir = try omohi_dir.openDir("journal", .{ .iterate = true });
    defer journal_dir.close();
    var it = journal_dir.iterate();
    try std.testing.expect((try it.next()) != null);
}
