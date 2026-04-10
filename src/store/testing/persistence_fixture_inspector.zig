const std = @import("std");

/// Returns the value for a `key=value` property line when present.
/// Memory: borrowed.
/// Lifetime: valid while `bytes` remains valid.
/// Errors: none.
/// Caller responsibilities: keep `bytes` alive while using the returned slice.
pub fn propertyValue(bytes: []const u8, key: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, bytes, '\n');
    while (iter.next()) |raw| {
        const line = std.mem.trim(u8, std.mem.trimRight(u8, raw, "\r"), " \t");
        if (line.len <= key.len or line[key.len] != '=') continue;
        if (!std.mem.startsWith(u8, line, key)) continue;
        return line[key.len + 1 ..];
    }
    return null;
}

/// Returns the first non-empty HEAD line from stored file bytes.
/// Memory: borrowed.
/// Lifetime: valid while `bytes` remains valid.
/// Errors: none.
/// Caller responsibilities: keep `bytes` alive while using the returned slice.
pub fn headValue(bytes: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, bytes, '\n');
    while (iter.next()) |raw| {
        const line = std.mem.trim(u8, std.mem.trimRight(u8, raw, "\r"), " \t");
        if (line.len == 0) continue;
        return line;
    }
    return null;
}

/// Reads the single file name inside a fixture directory into the caller-owned buffer.
/// Memory: borrowed via `out`.
/// Lifetime: writes into `out` during the call only.
/// Errors: `MissingFile`, `InvalidEntry`, `TooManyFiles`, `InvalidHashLength`, and directory I/O errors.
/// Caller responsibilities: provide a fixed-size output buffer matching the expected file name length.
pub fn onlyFileNameInDir(dir: std.fs.Dir, path: []const u8, out: *[64]u8) !void {
    var target = try dir.openDir(path, .{ .iterate = true });
    defer target.close();

    var it = target.iterate();
    const first = (try it.next()) orelse return error.MissingFile;
    if (first.kind != .file) return error.InvalidEntry;
    if ((try it.next()) != null) return error.TooManyFiles;
    if (first.name.len != out.len) return error.InvalidHashLength;
    @memcpy(out, first.name);
}

/// Asserts that a fixture directory contains no entries.
/// Memory: none.
/// Lifetime: n/a.
/// Errors: directory I/O errors and test assertion failures.
/// Caller responsibilities: pass an existing directory path.
pub fn expectDirEmpty(dir: std.fs.Dir, path: []const u8) !void {
    var target = try dir.openDir(path, .{ .iterate = true });
    defer target.close();

    var it = target.iterate();
    try std.testing.expect((try it.next()) == null);
}

/// Asserts that a fixture directory contains no file entries.
/// Memory: none.
/// Lifetime: n/a.
/// Errors: directory I/O errors and `ExpectedNoFiles`.
/// Caller responsibilities: pass an existing directory path.
pub fn expectDirHasNoFiles(dir: std.fs.Dir, path: []const u8) !void {
    var target = try dir.openDir(path, .{ .iterate = true });
    defer target.close();

    var it = target.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file) return error.ExpectedNoFiles;
    }
}

test "propertyValue returns matching key from fixture text" {
    const bytes = "snapshotId=abc\nmessage=test\n";
    const actual = propertyValue(bytes, "message") orelse return error.MissingProperty;
    try std.testing.expectEqualStrings("test", actual);
}

test "headValue skips empty lines" {
    const bytes = "\n  \nhead-id\n";
    const actual = headValue(bytes) orelse return error.MissingHead;
    try std.testing.expectEqualStrings("head-id", actual);
}
