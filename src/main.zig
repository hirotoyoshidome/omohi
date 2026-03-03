const std = @import("std");
const cli = @import("app/cli/run.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const code = cli.runFromProcessArgs(allocator);
    std.process.exit(code);
}
