const std = @import("std");

const less_args = [_][]const u8{ "less", "-RX" };

// Writes output to stdout directly or through `less` when paging is requested and supported.
pub fn writeOutput(
    allocator: std.mem.Allocator,
    output: []const u8,
    page_output: bool,
) !void {
    if (!shouldUsePager(output, page_output)) {
        try std.fs.File.stdout().writeAll(output);
        return;
    }

    if (try pageWithLess(allocator, output)) return;
    try std.fs.File.stdout().writeAll(output);
}

// Reports whether pager use is appropriate for the current output and terminal state.
fn shouldUsePager(output: []const u8, page_output: bool) bool {
    if (!page_output) return false;
    if (std.mem.indexOfScalar(u8, output, '\n') == null) return false;
    return std.posix.isatty(std.fs.File.stdout().handle);
}

// Tries to pipe the output through `less` and returns whether paging succeeded.
fn pageWithLess(allocator: std.mem.Allocator, output: []const u8) !bool {
    var child = std.process.Child.init(&less_args, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    child.spawn() catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };

    errdefer _ = child.kill() catch {};

    if (child.stdin) |*stdin_file| {
        try stdin_file.writeAll(output);
        stdin_file.close();
        child.stdin = null;
    }

    const term = try child.wait();
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

test "shouldUsePager requires tty flag and multi-line output" {
    try std.testing.expect(!shouldUsePager("one line", true));
    try std.testing.expect(!shouldUsePager("one line\n", false));
}

test "pager keeps less open even for one screen output" {
    try std.testing.expectEqualStrings("less", less_args[0]);
    try std.testing.expectEqualStrings("-RX", less_args[1]);
}
