const std = @import("std");

pub const LongOption = struct {
    key: []const u8,
    value: ?[]const u8,
};

// Compares tokens case-insensitively for CLI aliases and option keys.
pub fn equalsIgnoreAsciiCase(lhs: []const u8, rhs: []const u8) bool {
    return std.ascii.eqlIgnoreCase(lhs, rhs);
}

// Reports whether the token is the `--` option terminator.
pub fn isDoubleDash(token: []const u8) bool {
    return std.mem.eql(u8, token, "--");
}

// Reports whether the token is a specific one-letter short option.
pub fn isShortOption(token: []const u8, short_name: u8) bool {
    return token.len == 2 and token[0] == '-' and std.ascii.toLower(token[1]) == std.ascii.toLower(short_name);
}

// Parses a `--key` or `--key=value` token and returns null for non-long options.
pub fn parseLongOption(token: []const u8) ?LongOption {
    if (!std.mem.startsWith(u8, token, "--")) return null;
    const body = token[2..];
    if (body.len == 0) return null;

    if (std.mem.indexOfScalar(u8, body, '=')) |eq| {
        const key = body[0..eq];
        const value = body[eq + 1 ..];
        if (key.len == 0) return null;
        return .{ .key = key, .value = value };
    }

    return .{ .key = body, .value = null };
}

// Returns the inline option value or consumes the next token as the option value.
pub fn optionValue(args: []const []const u8, idx: *usize, inline_value: ?[]const u8) ![]const u8 {
    if (inline_value) |value| return value;

    idx.* += 1;
    if (idx.* >= args.len) return error.MissingValue;
    return args[idx.*];
}
