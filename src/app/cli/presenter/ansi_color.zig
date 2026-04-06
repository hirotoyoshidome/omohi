const std = @import("std");

pub const Color = enum {
    green,
    red,
};

/// Writes `text` with an ANSI color when enabled.
/// Memory: borrowed
/// Lifetime: valid for the duration of this call
/// Errors: writer failures
/// Caller responsibilities: provide a writable output target
pub fn writeColored(writer: anytype, text: []const u8, color: Color, enabled: bool) !void {
    if (!enabled) {
        try writer.writeAll(text);
        return;
    }

    try writer.writeAll(startCode(color));
    try writer.writeAll(text);
    try writer.writeAll(reset_code);
}

const reset_code = "\x1b[0m";

// Returns the ANSI escape sequence for the selected color.
fn startCode(color: Color) []const u8 {
    return switch (color) {
        .green => "\x1b[32m",
        .red => "\x1b[31m",
    };
}

test "writeColored leaves text unchanged when disabled" {
    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();

    try writeColored(out.writer(), "staged:", .green, false);

    try std.testing.expectEqualStrings("staged:", out.items);
}

test "writeColored wraps text with ANSI escapes when enabled" {
    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();

    try writeColored(out.writer(), "changed:", .red, true);

    try std.testing.expectEqualStrings("\x1b[31mchanged:\x1b[0m", out.items);
}
