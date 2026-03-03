const std = @import("std");

pub const CommandResult = struct {
    output: []u8,
    to_stderr: bool,
    exit_code: u8,

    pub fn deinit(self: *CommandResult, allocator: std.mem.Allocator) void {
        allocator.free(self.output);
    }
};
