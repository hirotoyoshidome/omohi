const std = @import("std");
const testing = std.testing;

/// Atomically writes `content` to `path` under the provided directory.
/// Memory: borrows `content`, caller retains ownership.
pub fn atomicWrite(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    path: []const u8,
    content: []const u8,
) !void {
    var stream = std.io.fixedBufferStream(content);
    try atomicWriteFromReader(allocator, dir, path, stream.reader());
}

// Streams data from the reader into a temp file, then renames and fsyncs the parent directory.
pub fn atomicWriteFromReader(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    path: []const u8,
    reader: anytype,
) !void {
    try ensureParentDirs(dir, path);

    const tmp_path = try makeTempPath(allocator, path);
    defer allocator.free(tmp_path);

    var file = try dir.createFile(tmp_path, .{
        .truncate = true,
        .exclusive = true,
    });
    defer file.close();

    errdefer dir.deleteFile(tmp_path) catch {};

    var buffer: [16 * 1024]u8 = undefined;
    switch (@typeInfo(@TypeOf(reader))) {
        .pointer => {
            while (true) {
                const read_len = try readChunk(reader, &buffer);
                if (read_len == 0) break;
                try file.writeAll(buffer[0..read_len]);
            }
        },
        else => {
            var input = reader;
            while (true) {
                const read_len = try readChunk(&input, &buffer);
                if (read_len == 0) break;
                try file.writeAll(buffer[0..read_len]);
            }
        },
    }
    try file.sync();

    try dir.rename(tmp_path, path);
    try syncParentDir(dir, path);
}

// Reads one chunk from either a standard reader or an interface-based reader.
fn readChunk(reader: anytype, buffer: []u8) !usize {
    const ReaderType = @TypeOf(reader);
    const BaseType = switch (@typeInfo(ReaderType)) {
        .pointer => |pointer| pointer.child,
        else => ReaderType,
    };

    if (comptime @hasDecl(BaseType, "read")) {
        return reader.read(buffer);
    }
    if (comptime @hasField(BaseType, "interface")) {
        var reader_value = reader;
        return reader_value.interface.readSliceShort(buffer);
    }

    @compileError("atomicWriteFromReader requires a reader with read() or interface.readSliceShort()");
}

// Ensures that the parent directories for the target relative path exist.
fn ensureParentDirs(dir: std.fs.Dir, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len == 0) return;
        try dir.makePath(parent);
    }
}

// Fsyncs the parent directory for the target relative path.
fn syncParentDir(dir: std.fs.Dir, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len == 0) {
            try syncDir(dir);
            return;
        }
        var parent_dir = try dir.openDir(parent, .{});
        defer parent_dir.close();
        try syncDir(parent_dir);
    } else {
        try syncDir(dir);
    }
}

// Builds an owned temporary path alongside the destination file.
fn makeTempPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var rand: [8]u8 = undefined;
    std.crypto.random.bytes(&rand);
    var hex: [rand.len * 2]u8 = undefined;
    encodeHexLower(&hex, &rand);
    return std.fmt.allocPrint(allocator, "{s}.tmp-{s}", .{ path, hex });
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

// Fsyncs a directory and tolerates platforms that reject directory fsync.
fn syncDir(dir: std.fs.Dir) !void {
    const rc = std.posix.system.fsync(dir.fd);
    switch (std.posix.errno(rc)) {
        .SUCCESS, .BADF, .INVAL, .ROFS => return,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

test "atomicWrite writes new file and replaces existing file" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = testing.allocator;
    const first = "first-version";
    try atomicWrite(allocator, tmp.dir, "level1/file.txt", first);

    const content = try tmp.dir.readFileAlloc(allocator, "level1/file.txt", 1024);
    defer allocator.free(content);
    try testing.expectEqualStrings(first, content);

    const second = "second-version";
    try atomicWrite(allocator, tmp.dir, "level1/file.txt", second);
    const updated = try tmp.dir.readFileAlloc(allocator, "level1/file.txt", 1024);
    defer allocator.free(updated);
    try testing.expectEqualStrings(second, updated);
}

test "atomicWriteFromReader writes content from reader" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = testing.allocator;
    const payload = "streamed-content";
    var stream = std.io.fixedBufferStream(payload);

    try atomicWriteFromReader(allocator, tmp.dir, "level1/file.txt", stream.reader());

    const stored = try tmp.dir.readFileAlloc(allocator, "level1/file.txt", 1024);
    defer allocator.free(stored);
    try testing.expectEqualStrings(payload, stored);
}

test "atomicWriteFromReader removes temp file on read failure" {
    const FailingReader = struct {
        emitted: bool = false,

        fn read(self: *@This(), dest: []u8) error{InjectedReadFailure}!usize {
            if (!self.emitted) {
                self.emitted = true;
                const payload = "partial";
                @memcpy(dest[0..payload.len], payload);
                return payload.len;
            }
            return error.InjectedReadFailure;
        }
    };

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var reader = FailingReader{};
    try testing.expectError(
        error.InjectedReadFailure,
        atomicWriteFromReader(testing.allocator, tmp.dir, "level1/file.txt", &reader),
    );

    try testing.expectError(error.FileNotFound, tmp.dir.access("level1/file.txt", .{}));

    var level1 = try tmp.dir.openDir("level1", .{ .iterate = true });
    defer level1.close();
    var it = level1.iterate();
    try testing.expect((try it.next()) == null);
}
