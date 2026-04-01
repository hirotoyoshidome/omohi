const std = @import("std");
const constrained_types = @import("constrained_types.zig");

/// ContentEntry represents a staged file reference inside a snapshot.
/// Memory: borrowed slices owned by the caller.
pub const ContentEntry = struct {
    path: constrained_types.TrackedFilePath,
    content_hash: constrained_types.ContentHash,

    pub fn init(path: []const u8, content_hash: []const u8) !ContentEntry {
        return .{
            .path = try constrained_types.TrackedFilePath.init(path),
            .content_hash = try constrained_types.ContentHash.init(content_hash),
        };
    }

    /// Returns true when `lhs.path` comes before `rhs.path`.
    pub fn isPathLessThan(lhs: ContentEntry, rhs: ContentEntry) bool {
        return std.mem.lessThan(u8, lhs.path.asSlice(), rhs.path.asSlice());
    }
};
