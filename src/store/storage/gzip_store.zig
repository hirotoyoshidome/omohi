const std = @import("std");

const max_stored_block_size = 65_535;

/// Streams a gzip file using uncompressed deflate stored blocks.
/// This keeps gzip restore compatibility without depending on external tools.
pub const Writer = struct {
    raw: *std.Io.Writer,
    interface: std.Io.Writer,
    buffer: [32 * 1024]u8 = undefined,
    crc: std.hash.Crc32 = std.hash.Crc32.init(),
    input_size: u32 = 0,
    finished: bool = false,

    /// Initializes a gzip writer and writes the gzip header immediately.
    /// Memory: borrowed
    /// Lifetime: valid until `finish` and while `raw` remains valid
    /// Errors: write failures from the underlying writer
    /// Caller responsibilities: call `finish` exactly once after all writes
    pub fn init(self: *Writer, raw: *std.Io.Writer) !void {
        try raw.writeAll(&.{
            0x1f, 0x8b, // gzip magic
            0x08, // deflate
            0x00, // flags
            0x00, 0x00, 0x00, 0x00, // mtime
            0x00, // xfl
            0x03, // Unix
        });

        self.* = .{
            .raw = raw,
            .interface = .{
                .vtable = &.{
                    .drain = drain,
                    .flush = flush,
                },
                .buffer = &.{},
            },
        };
        self.interface.buffer = &self.buffer;
    }

    /// Finishes the gzip stream by writing the final empty block and footer.
    /// Memory: borrowed
    /// Lifetime: valid until this writer is discarded
    /// Errors: write failures from the underlying writer
    /// Caller responsibilities: do not write more bytes after finishing
    pub fn finish(self: *Writer) !void {
        if (self.finished) return;
        try self.interface.flush();
        try self.writeStoredBlock("", true);
        try self.raw.writeInt(u32, self.crc.final(), .little);
        try self.raw.writeInt(u32, self.input_size, .little);
        try self.raw.flush();
        self.finished = true;
    }

    // Drains buffered and direct writer data into gzip stored blocks.
    fn drain(interface: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *Writer = @fieldParentPtr("interface", interface);
        const buffered = interface.buffered();
        if (buffered.len != 0) {
            self.writeData(buffered) catch return error.WriteFailed;
            interface.end = 0;
        }

        var consumed: usize = 0;
        for (data, 0..) |chunk, index| {
            const repeat = if (index == data.len - 1) splat else 1;
            for (0..repeat) |_| {
                self.writeData(chunk) catch return error.WriteFailed;
                consumed += chunk.len;
            }
        }
        return consumed;
    }

    // Flushes buffered bytes into the underlying gzip stream.
    fn flush(interface: *std.Io.Writer) std.Io.Writer.Error!void {
        const self: *Writer = @fieldParentPtr("interface", interface);
        const buffered = interface.buffered();
        if (buffered.len == 0) return;
        self.writeData(buffered) catch return error.WriteFailed;
        interface.end = 0;
    }

    // Splits input into deflate stored blocks and updates gzip accounting.
    fn writeData(self: *Writer, bytes: []const u8) !void {
        var remaining = bytes;
        while (remaining.len != 0) {
            const chunk_len = @min(remaining.len, max_stored_block_size);
            const chunk = remaining[0..chunk_len];
            try self.writeStoredBlock(chunk, false);
            self.crc.update(chunk);
            self.input_size +%= @truncate(chunk.len);
            remaining = remaining[chunk_len..];
        }
    }

    // Writes one byte-aligned deflate stored block.
    fn writeStoredBlock(self: *Writer, bytes: []const u8, final: bool) !void {
        std.debug.assert(bytes.len <= max_stored_block_size);
        const len: u16 = @intCast(bytes.len);
        try self.raw.writeByte(if (final) 0x01 else 0x00);
        try self.raw.writeInt(u16, len, .little);
        try self.raw.writeInt(u16, ~len, .little);
        try self.raw.writeAll(bytes);
    }
};

test "gzip store writer produces decompressible gzip bytes" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var gzip: Writer = undefined;
    try gzip.init(&out.writer);
    try gzip.interface.writeAll("hello gzip");
    try gzip.finish();

    var input: std.Io.Reader = .fixed(out.writer.buffered());
    var decompressed: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer decompressed.deinit();
    var buffer: [std.compress.flate.max_window_len]u8 = undefined;
    var inflater: std.compress.flate.Decompress = .init(&input, .gzip, &buffer);
    _ = try inflater.reader.streamRemaining(&decompressed.writer);

    try std.testing.expectEqualStrings("hello gzip", decompressed.writer.buffered());
}
