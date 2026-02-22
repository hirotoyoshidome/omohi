const std = @import("std");

/// ContentEntry represents a staged file reference inside a snapshot.
/// Memory: borrowed slices owned by the caller.
pub const ContentEntry = struct {
    path: []const u8,
    content_hash: [64]u8,

    /// Returns true when `lhs.path` comes before `rhs.path`.
    pub fn lessThanByPath(lhs: ContentEntry, rhs: ContentEntry) bool {
        return std.mem.lessThan(u8, lhs.path, rhs.path);
    }
};
