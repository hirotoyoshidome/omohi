const std = @import("std");
const sha2 = std.crypto.hash.sha2;

pub const max_tag_name_len: usize = 255;
const content_objects_prefix = "/objects/";

/// TrackedFileId is a UUID hex string without separators (32 chars).
pub const TrackedFileId = struct {
    value: [32]u8,

    pub fn init(raw: []const u8) !TrackedFileId {
        var buf: [32]u8 = undefined;
        try parseHexFixed(raw, &buf, error.InvalidTrackedFileId);
        return .{ .value = buf };
    }

    pub fn generate() TrackedFileId {
        var bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&bytes);

        var hex: [32]u8 = undefined;
        encodeHexLower(&hex, &bytes);
        return .{ .value = hex };
    }

    pub fn asSlice(self: *const TrackedFileId) []const u8 {
        return self.value[0..];
    }
};

pub const StagedFileId = struct {
    value: [64]u8,

    pub fn init(raw: []const u8) !StagedFileId {
        var buf: [64]u8 = undefined;
        try parseHexFixed(raw, &buf, error.InvalidStagedFileId);
        return .{ .value = buf };
    }

    pub fn asSlice(self: *const StagedFileId) []const u8 {
        return self.value[0..];
    }
};

pub const CommitId = struct {
    value: [64]u8,

    pub fn init(raw: []const u8) !CommitId {
        var buf: [64]u8 = undefined;
        try parseHexFixed(raw, &buf, error.InvalidCommitId);
        return .{ .value = buf };
    }

    pub fn asSlice(self: *const CommitId) []const u8 {
        return self.value[0..];
    }
};

pub const SnapshotId = struct {
    value: [64]u8,

    pub fn init(raw: []const u8) !SnapshotId {
        var buf: [64]u8 = undefined;
        try parseHexFixed(raw, &buf, error.InvalidSnapshotId);
        return .{ .value = buf };
    }

    pub fn asSlice(self: *const SnapshotId) []const u8 {
        return self.value[0..];
    }
};

pub const ContentHash = struct {
    value: [64]u8,

    pub fn init(raw: []const u8) !ContentHash {
        var buf: [64]u8 = undefined;
        try parseHexFixed(raw, &buf, error.InvalidContentHash);
        return .{ .value = buf };
    }

    pub fn from(content: []const u8) ContentHash {
        var hasher = sha2.Sha256.init(.{});
        hasher.update(content);
        var digest: [sha2.Sha256.digest_length]u8 = undefined;
        hasher.final(&digest);

        var out: [64]u8 = undefined;
        encodeHexLower(&out, &digest);
        return .{ .value = out };
    }

    pub fn asSlice(self: *const ContentHash) []const u8 {
        return self.value[0..];
    }
};

pub const TagName = struct {
    value: []const u8,

    pub fn init(raw: []const u8) !TagName {
        if (raw.len == 0) return error.InvalidTagName;
        if (raw.len > max_tag_name_len) return error.InvalidTagName;
        return .{ .value = raw };
    }

    pub fn asSlice(self: TagName) []const u8 {
        return self.value;
    }
};

pub const TrackedFilePath = struct {
    value: []const u8,

    pub fn init(raw: []const u8) !TrackedFilePath {
        try validateAbsolutePathWithoutParent(raw, error.InvalidTrackedFilePath);
        return .{ .value = raw };
    }

    pub fn asSlice(self: TrackedFilePath) []const u8 {
        return self.value;
    }
};

pub const ContentPath = struct {
    value: []const u8,

    pub fn init(raw: []const u8) !ContentPath {
        try validateAbsolutePathWithoutParent(raw, error.InvalidContentPath);
        if (!std.mem.startsWith(u8, raw, content_objects_prefix)) return error.InvalidContentPath;
        if (raw.len <= content_objects_prefix.len) return error.InvalidContentPath;
        return .{ .value = raw };
    }

    pub fn asSlice(self: ContentPath) []const u8 {
        return self.value;
    }
};

// Validates absolute paths while rejecting parent traversal segments.
fn validateAbsolutePathWithoutParent(raw: []const u8, comptime err_tag: anytype) !void {
    if (raw.len == 0) return err_tag;
    if (raw[0] != '/') return err_tag;
    if (std.mem.indexOf(u8, raw, "..") != null) return err_tag;
}

// Parses a fixed-length hex string into lowercase bytes.
fn parseHexFixed(source: []const u8, dest: []u8, comptime err_tag: anytype) !void {
    if (source.len != dest.len) return err_tag;
    for (source, 0..) |ch, idx| {
        if (!std.ascii.isHex(ch)) return err_tag;
        dest[idx] = std.ascii.toLower(ch);
    }
}

// Encodes bytes into lowercase hexadecimal characters.
fn encodeHexLower(dest: []u8, source: []const u8) void {
    const alphabet = "0123456789abcdef";
    var di: usize = 0;
    for (source) |byte| {
        dest[di] = alphabet[@as(usize, byte >> 4)];
        dest[di + 1] = alphabet[@as(usize, byte & 0x0f)];
        di += 2;
    }
}

test "TrackedFilePath validates absolute path and parent traversal" {
    try std.testing.expectError(error.InvalidTrackedFilePath, TrackedFilePath.init(""));
    try std.testing.expectError(error.InvalidTrackedFilePath, TrackedFilePath.init("a/b"));
    try std.testing.expectError(error.InvalidTrackedFilePath, TrackedFilePath.init("/a/../b"));
    const path = try TrackedFilePath.init("/a/b");
    try std.testing.expectEqualStrings("/a/b", path.asSlice());
}

test "ContentPath requires objects directory prefix" {
    try std.testing.expectError(error.InvalidContentPath, ContentPath.init("/file/a.txt"));
    const path = try ContentPath.init("/objects/aa/bb");
    try std.testing.expectEqualStrings("/objects/aa/bb", path.asSlice());
}

test "hash based value objects normalize uppercase hex" {
    var upper: [64]u8 = undefined;
    @memset(&upper, 'A');
    const hash = try ContentHash.init(&upper);
    try std.testing.expectEqual(@as(u8, 'a'), hash.asSlice()[0]);

    const commit_id = try CommitId.init(hash.asSlice());
    try std.testing.expectEqualSlices(u8, hash.asSlice(), commit_id.asSlice());
}

test "TagName enforces max length" {
    var long_buf: [256]u8 = undefined;
    @memset(&long_buf, 'x');
    try std.testing.expectError(error.InvalidTagName, TagName.init(&long_buf));
    _ = try TagName.init("release-1");
}

test "TrackedFileId generates 32-char lowercase hex" {
    const id = TrackedFileId.generate();
    try std.testing.expectEqual(@as(usize, 32), id.asSlice().len);
    for (id.asSlice()) |ch| try std.testing.expect(std.ascii.isHex(ch));
}
