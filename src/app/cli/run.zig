const std = @import("std");
const parser = @import("parser/parse.zig");
const parser_types = @import("parser/types.zig");
const dispatch = @import("runtime/dispatch.zig");
const exit_code = @import("exit_code.zig");
const error_map = @import("error_map.zig");

pub fn run(allocator: std.mem.Allocator, argv: []const []const u8) u8 {
    var parsed = parser.parseArgs(allocator, argv) catch |err| {
        writeErrWithPrefix("cli parse error: ", @errorName(err));
        return exit_code.usage_error;
    };
    defer parser_types.deinitParsedRequest(allocator, &parsed);

    var result = dispatch.dispatch(allocator, parsed) catch |err| {
        const mapped = error_map.exitCodeFor(err);
        writeErrLine(@errorName(err));
        return mapped;
    };
    defer result.deinit(allocator);

    if (result.to_stderr) {
        writeErr(result.output);
    } else {
        writeOut(result.output);
    }

    return result.exit_code;
}

fn writeOut(text: []const u8) void {
    std.fs.File.stdout().writeAll(text) catch {};
}

fn writeErr(text: []const u8) void {
    std.fs.File.stderr().writeAll(text) catch {};
}

fn writeErrLine(text: []const u8) void {
    writeErr(text);
    writeErr("\n");
}

fn writeErrWithPrefix(prefix: []const u8, value: []const u8) void {
    var buf: [256]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "{s}{s}\n", .{ prefix, value }) catch {
        writeErr(prefix);
        writeErrLine(value);
        return;
    };
    writeErr(line);
}

pub fn runFromProcessArgs(allocator: std.mem.Allocator) u8 {
    const args = std.process.argsAlloc(allocator) catch return exit_code.system_error;
    defer std.process.argsFree(allocator, args);

    if (args.len <= 1) return run(allocator, &.{});

    const sliced = args[1..];
    const normalized = allocator.alloc([]const u8, sliced.len) catch return exit_code.system_error;
    defer allocator.free(normalized);

    for (sliced, 0..) |arg, idx| normalized[idx] = arg;
    return run(allocator, normalized);
}
