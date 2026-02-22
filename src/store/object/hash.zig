const std = @import("std");
const sha2 = std.crypto.hash.sha2;

const ContentEntry = @import("content_entry.zig").ContentEntry;

/// Calculates SHA256 and returns lowercase hex.
pub fn sha256Hex(input: []const u8) [64]u8 {
    var hasher = sha2.Sha256.init(.{});
    hasher.update(input);
    var digest: [sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);

    var out: [sha2.Sha256.digest_length * 2]u8 = undefined;
    _ = std.fmt.bufPrint(&out, "{s}", .{std.fmt.fmtSliceHexLower(&digest)}) catch unreachable;
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
