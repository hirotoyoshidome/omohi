const std = @import("std");

const store_api = @import("../store/api.zig");

pub const JournalEntry = store_api.JournalEntry;
pub const JournalList = store_api.JournalEntryList;

/// Loads recent journal entries from the store.
pub fn journal(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    limit: usize,
) !JournalList {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    return store_api.journal(allocator, omohi_dir, limit);
}

// Releases the owned journal entries returned by `journal`.
pub fn freeJournalList(allocator: std.mem.Allocator, list: *JournalList) void {
    store_api.freeJournalEntryList(allocator, list);
}

test "journal delegates to store and returns recent entries" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);
    try store_api.appendJournal(allocator, omohi_dir, "track", "{\"path\":\"/tmp/ops\"}");

    var lines = try journal(allocator, omohi_dir, 20);
    defer freeJournalList(allocator, &lines);

    try std.testing.expectEqual(@as(usize, 1), lines.items.len);
    try std.testing.expectEqualStrings("track", lines.items[0].command_type);
    try std.testing.expect(std.mem.indexOf(u8, lines.items[0].payload_json, "\"/tmp/ops\"") != null);
}
