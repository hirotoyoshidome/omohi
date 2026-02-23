const std = @import("std");
const testing = std.testing;
const sha2 = std.crypto.hash.sha2;

const ContentEntry = @import("content_entry.zig").ContentEntry;

/// Calculates SHA256 and returns lowercase hex.
pub fn sha256Hex(input: []const u8) [64]u8 {
    var hasher = sha2.Sha256.init(.{});
    hasher.update(input);
    var digest: [sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);

    var out: [sha2.Sha256.digest_length * 2]u8 = undefined;
    encodeHexLower(&out, &digest);
    return out;
}

/// SnapshotId is generated from entries sorted by path.
/// Memory: value return.
pub fn snapshotIdFrom(entries: []const ContentEntry) [64]u8 {
    var hasher = sha2.Sha256.init(.{});

    for (entries) |entry| {
        hasher.update(entry.path);
        hasher.update("\n");
        hasher.update(entry.content_hash[0..]);
        hasher.update("\n");
    }

    var digest: [sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    return sha256Hex(digest[0..]);
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

/// CommitId is derived from snapshotId + message.
/// Memory: value return.
pub fn commitIdFrom(snapshotId: []const u8, message: []const u8) [64]u8 {
    var hasher = sha2.Sha256.init(.{});
    hasher.update(snapshotId);
    hasher.update("\n");
    hasher.update(message);
    hasher.update("\n");

    var digest: [sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    return sha256Hex(digest[0..]);
}

/// StagedFileId is derived from path + content hash.
/// Memory: value return.
pub fn stagedFileIdFrom(path: []const u8, contentHash: []const u8) [64]u8 {
    var hasher = sha2.Sha256.init(.{});
    hasher.update(path);
    hasher.update("\n");
    hasher.update(contentHash);
    hasher.update("\n");

    var digest: [sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    return sha256Hex(digest[0..]);
}

test "sha256Hex matches known digest" {
    const digest = sha256Hex("hello");
    try testing.expectEqualStrings(
        "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
        &digest,
    );
}

test "snapshotIdFrom concatenates entries deterministically" {
    var zero_hash: [64]u8 = undefined;
    @memset(&zero_hash, '0');
    var eff_hash: [64]u8 = undefined;
    @memset(&eff_hash, 'f');

    var entries = [_]ContentEntry{
        .{ .path = "/a.txt", .content_hash = zero_hash },
        .{ .path = "/b.txt", .content_hash = eff_hash },
    };
    const id = snapshotIdFrom(&entries);

    var hasher = sha2.Sha256.init(.{});
    hasher.update("/a.txt\n");
    hasher.update(zero_hash[0..]);
    hasher.update("\n/b.txt\n");
    hasher.update(eff_hash[0..]);
    hasher.update("\n");
    var digest: [sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    const expected = sha256Hex(digest[0..]);
    try testing.expectEqual(expected, id);
}

test "stagedFileIdFrom reflects path changes" {
    const hash_a = stagedFileIdFrom("/a.txt", "00");
    const hash_b = stagedFileIdFrom("/b.txt", "00");
    try testing.expect(!std.mem.eql(u8, &hash_a, &hash_b));
}
