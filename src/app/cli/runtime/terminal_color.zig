const std = @import("std");

pub const Stream = enum {
    stdout,
    stderr,
};

/// Reports whether the selected standard stream supports ANSI color output.
/// Memory: borrowed
/// Lifetime: valid only for the current process state
/// Errors: none
/// Caller responsibilities: none
pub fn supportsColor(stream: Stream) bool {
    const file = switch (stream) {
        .stdout => std.fs.File.stdout(),
        .stderr => std.fs.File.stderr(),
    };
    return std.posix.isatty(file.handle);
}

test "supportsColor accepts both standard streams" {
    _ = supportsColor(.stdout);
    _ = supportsColor(.stderr);
}
