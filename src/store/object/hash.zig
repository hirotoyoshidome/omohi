const std = @import("std");
const testing = std.testing;
const sha2 = std.crypto.hash.sha2;

const ContentEntry = @import("content_entry.zig").ContentEntry;
const constrained_types = @import("constrained_types.zig");
const id_field_separator = ":";
const snapshot_entry_separator = "|";

/// Calculates SHA256 and returns lowercase hex.
pub fn sha256Hex(input: []const u8) [64]u8 {
    var hasher = sha2.Sha256.init(.{});
    hasher.update(input);
    return sha256HexFromHasher(&hasher);
}

/// SnapshotId is generated from entries sorted by path.
/// Memory: value return.
pub fn snapshotIdFrom(allocator: std.mem.Allocator, entries: []const ContentEntry) ![64]u8 {
    const sorted_entries = try allocator.dupe(ContentEntry, entries);
    defer allocator.free(sorted_entries);
    std.mem.sort(ContentEntry, sorted_entries, {}, isPathLessThan);

    var hasher = sha2.Sha256.init(.{});
    for (sorted_entries, 0..) |entry, idx| {
        if (idx != 0) hasher.update(snapshot_entry_separator);
        hasher.update(entry.path.asSlice());
        hasher.update(id_field_separator);
        hasher.update(entry.content_hash.asSlice());
    }

    var digest: [sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    var out: [sha2.Sha256.digest_length * 2]u8 = undefined;
    encodeHexLower(&out, &digest);
    return out;
}

pub fn snapshotIdVoFrom(
    allocator: std.mem.Allocator,
    entries: []const ContentEntry,
) !constrained_types.SnapshotId {
    return .{ .value = try snapshotIdFrom(allocator, entries) };
}

fn isPathLessThan(_: void, lhs: ContentEntry, rhs: ContentEntry) bool {
    return ContentEntry.isPathLessThan(lhs, rhs);
}

fn encodeHexLower(dest: []u8, source: []const u8) void {
    const alphabet = "0123456789abcdef";
    var di: usize = 0;
    for (source) |byte| {
        dest[di] = alphabet[@as(usize, byte >> 4)];
        dest[di + 1] = alphabet[@as(usize, byte & 0x0f)];
        di += 2;
    }
}

pub fn sha256HexFromHasher(hasher: *sha2.Sha256) [64]u8 {
    var digest: [sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);

    var out: [sha2.Sha256.digest_length * 2]u8 = undefined;
    encodeHexLower(&out, &digest);
    return out;
}

/// CommitId is derived from snapshotId + message.
/// Memory: value return.
pub fn commitIdFrom(snapshotId: []const u8, message: []const u8) [64]u8 {
    var hasher = sha2.Sha256.init(.{});
    hasher.update(snapshotId);
    hasher.update(id_field_separator);
    hasher.update(message);

    var digest: [sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    var out: [sha2.Sha256.digest_length * 2]u8 = undefined;
    encodeHexLower(&out, &digest);
    return out;
}

pub fn commitIdVoFrom(snapshot_id: constrained_types.SnapshotId, message: []const u8) constrained_types.CommitId {
    return .{ .value = commitIdFrom(snapshot_id.asSlice(), message) };
}

/// StagedFileId is derived from path + content hash.
/// Memory: value return.
pub fn stagedFileIdFrom(path: []const u8, contentHash: []const u8) [64]u8 {
    var hasher = sha2.Sha256.init(.{});
    hasher.update(contentHash);
    hasher.update(id_field_separator);
    hasher.update(path);

    var digest: [sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    var out: [sha2.Sha256.digest_length * 2]u8 = undefined;
    encodeHexLower(&out, &digest);
    return out;
}

pub fn stagedFileIdVoFrom(
    path: constrained_types.TrackedFilePath,
    content_hash: constrained_types.ContentHash,
) constrained_types.StagedFileId {
    return .{ .value = stagedFileIdFrom(path.asSlice(), content_hash.asSlice()) };
}

test "sha256Hex matches known digest" {
    const digest = sha256Hex("hello");
    try testing.expectEqualStrings(
        "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
        &digest,
    );
}

test "snapshotIdFrom sorts by path and uses pipe-separated path-hash pairs" {
    var zero_hash: [64]u8 = undefined;
    @memset(&zero_hash, '0');
    var eff_hash: [64]u8 = undefined;
    @memset(&eff_hash, 'f');

    var entries = [_]ContentEntry{
        .{
            .path = try constrained_types.TrackedFilePath.init("/tmp/b.txt"),
            .content_hash = try constrained_types.ContentHash.init(&eff_hash),
        },
        .{
            .path = try constrained_types.TrackedFilePath.init("/tmp/a.txt"),
            .content_hash = try constrained_types.ContentHash.init(&zero_hash),
        },
    };
    const id = try snapshotIdFrom(testing.allocator, &entries);

    const joined = "/tmp/a.txt" ++ id_field_separator ++
        "0000000000000000000000000000000000000000000000000000000000000000" ++
        snapshot_entry_separator ++
        "/tmp/b.txt" ++ id_field_separator ++
        "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    const expected = sha256Hex(joined);
    try testing.expectEqualSlices(u8, expected[0..], id[0..]);
}

test "stagedFileIdFrom reflects path changes" {
    const hash_a = stagedFileIdFrom("/a.txt", "00");
    const hash_b = stagedFileIdFrom("/b.txt", "00");
    try testing.expect(!std.mem.eql(u8, &hash_a, &hash_b));
}

test "stagedFileIdFrom uses content-hash colon path format" {
    const id = stagedFileIdFrom("/docs/readme.md", "abc123");
    const expected = sha256Hex("abc123" ++ id_field_separator ++ "/docs/readme.md");
    try testing.expectEqualSlices(u8, expected[0..], id[0..]);
}

test "commitIdFrom uses snapshot-id colon message format" {
    const id = commitIdFrom("snapshot-1", "hello");
    const expected = sha256Hex("snapshot-1" ++ id_field_separator ++ "hello");
    try testing.expectEqualSlices(u8, expected[0..], id[0..]);
}

test "vo wrappers keep id generation inside store" {
    const path = try constrained_types.TrackedFilePath.init("/docs/readme.md");
    var hash_raw: [64]u8 = undefined;
    @memset(&hash_raw, 'c');
    const content_hash = try constrained_types.ContentHash.init(&hash_raw);
    const staged_id = stagedFileIdVoFrom(path, content_hash);
    try testing.expectEqual(@as(usize, 64), staged_id.asSlice().len);
}
