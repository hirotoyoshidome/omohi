const std = @import("std");

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("time.h");
});

pub const FindBoundary = enum {
    since,
    until,
};

const ParsedLocalDateTime = struct {
    year: i32,
    month: i32,
    day: i32,
    hour: i32,
    minute: i32,
    second: i32,
    millisecond: i32,
};

/// Resolves a `find` boundary string into local-time epoch milliseconds.
pub fn parseFindBoundaryMillis(raw: []const u8, bound: FindBoundary) !i64 {
    const parsed = try parseFindBoundary(raw, bound);
    const seconds = try resolveLocalEpochSeconds(parsed);
    const millis = try std.math.mul(i64, seconds, 1000);
    return try std.math.add(i64, millis, parsed.millisecond);
}

// Parses one `find` boundary and expands date-only input to the proper inclusive edge.
fn parseFindBoundary(raw: []const u8, bound: FindBoundary) !ParsedLocalDateTime {
    if (raw.len == 10) {
        const year = try parseAsciiInt(raw[0..4]);
        const month = try parseAsciiInt(raw[5..7]);
        const day = try parseAsciiInt(raw[8..10]);
        try validateYmd(raw, year, month, day);

        return switch (bound) {
            .since => .{ .year = year, .month = month, .day = day, .hour = 0, .minute = 0, .second = 0, .millisecond = 0 },
            .until => .{ .year = year, .month = month, .day = day, .hour = 23, .minute = 59, .second = 59, .millisecond = 999 },
        };
    }

    if (raw.len == 19) {
        if (raw[4] != '-' or raw[7] != '-' or raw[10] != 'T' or raw[13] != ':' or raw[16] != ':') return error.InvalidDate;
        const year = try parseAsciiInt(raw[0..4]);
        const month = try parseAsciiInt(raw[5..7]);
        const day = try parseAsciiInt(raw[8..10]);
        try validateYmd(raw[0..10], year, month, day);

        const hour = try parseAsciiInt(raw[11..13]);
        const minute = try parseAsciiInt(raw[14..16]);
        const second = try parseAsciiInt(raw[17..19]);
        if (hour < 0 or hour > 23) return error.InvalidDate;
        if (minute < 0 or minute > 59) return error.InvalidDate;
        if (second < 0 or second > 59) return error.InvalidDate;

        return .{
            .year = year,
            .month = month,
            .day = day,
            .hour = hour,
            .minute = minute,
            .second = second,
            .millisecond = 0,
        };
    }

    return error.InvalidDate;
}

// Converts validated local date-time fields into epoch seconds and rejects DST ambiguity.
fn resolveLocalEpochSeconds(parsed: ParsedLocalDateTime) !i64 {
    const auto_seconds = (try localEpochSecondsForIsdst(parsed, -1)) orelse return error.InvalidDate;
    const standard_seconds = try localEpochSecondsForIsdst(parsed, 0);
    const daylight_seconds = try localEpochSecondsForIsdst(parsed, 1);

    if (standard_seconds != null and daylight_seconds != null and standard_seconds.? != daylight_seconds.?) {
        return error.InvalidDate;
    }

    return auto_seconds;
}

// Converts one local date-time with a requested DST mode into epoch seconds when representable.
fn localEpochSecondsForIsdst(parsed: ParsedLocalDateTime, isdst: c_int) !?i64 {
    var tm_value = buildTm(parsed, isdst);
    const raw_seconds = c.mktime(&tm_value);
    if (raw_seconds < 0) return null;
    if (!tmMatchesParsed(tm_value, parsed)) return null;

    var seconds_copy = raw_seconds;
    var roundtrip_tm: c.struct_tm = undefined;
    if (c.localtime_r(&seconds_copy, &roundtrip_tm) == null) return error.InvalidDate;
    if (!tmMatchesParsed(roundtrip_tm, parsed)) return null;
    if (isdst >= 0 and roundtrip_tm.tm_isdst != isdst) return null;

    return std.math.cast(i64, raw_seconds) orelse error.InvalidDate;
}

// Builds a libc `tm` from parsed local date-time fields.
fn buildTm(parsed: ParsedLocalDateTime, isdst: c_int) c.struct_tm {
    return .{
        .tm_sec = parsed.second,
        .tm_min = parsed.minute,
        .tm_hour = parsed.hour,
        .tm_mday = parsed.day,
        .tm_mon = parsed.month - 1,
        .tm_year = parsed.year - 1900,
        .tm_wday = 0,
        .tm_yday = 0,
        .tm_isdst = isdst,
        .tm_gmtoff = 0,
        .tm_zone = null,
    };
}

// Checks whether one `tm` round-trips back to the requested local date-time.
fn tmMatchesParsed(tm_value: c.struct_tm, parsed: ParsedLocalDateTime) bool {
    return tm_value.tm_year + 1900 == parsed.year and
        tm_value.tm_mon + 1 == parsed.month and
        tm_value.tm_mday == parsed.day and
        tm_value.tm_hour == parsed.hour and
        tm_value.tm_min == parsed.minute and
        tm_value.tm_sec == parsed.second;
}

// Validates one `YYYY-MM-DD` fragment and rejects impossible calendar dates.
fn validateYmd(raw: []const u8, year: i32, month: i32, day: i32) !void {
    if (raw.len != 10) return error.InvalidDate;
    if (raw[4] != '-' or raw[7] != '-') return error.InvalidDate;

    var idx: usize = 0;
    while (idx < raw.len) : (idx += 1) {
        if (idx == 4 or idx == 7) continue;
        if (!std.ascii.isDigit(raw[idx])) return error.InvalidDate;
    }

    if (month < 1 or month > 12) return error.InvalidDate;
    if (day < 1 or day > daysInMonth(year, month)) return error.InvalidDate;
}

// Parses a short ASCII digit slice into one local date/time component.
fn parseAsciiInt(slice: []const u8) !i32 {
    var value: i32 = 0;
    for (slice) |ch| {
        if (!std.ascii.isDigit(ch)) return error.InvalidDate;
        value = value * 10 + @as(i32, ch - '0');
    }
    return value;
}

// Reports whether the Gregorian year is a leap year.
fn isLeapYear(year: i32) bool {
    if (@mod(year, 4) != 0) return false;
    if (@mod(year, 100) != 0) return true;
    return @mod(year, 400) == 0;
}

// Returns the number of days in the given month for the given year.
fn daysInMonth(year: i32, month: i32) i32 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

test "parseFindBoundaryMillis accepts date-only lower and upper bounds" {
    const start = try parseFindBoundaryMillis("2026-03-11", .since);
    const end = try parseFindBoundaryMillis("2026-03-11", .until);

    try std.testing.expect(end > start);
    try std.testing.expectEqual(@as(i64, 86_399_999), end - start);
}

test "parseFindBoundaryMillis accepts local datetime input" {
    _ = try parseFindBoundaryMillis("2026-03-11T12:34:56", .since);
}

test "parseFindBoundaryMillis rejects impossible dates and unsupported formats" {
    try std.testing.expectError(error.InvalidDate, parseFindBoundaryMillis("2026-02-29", .since));
    try std.testing.expectError(error.InvalidDate, parseFindBoundaryMillis("2026-02-30", .since));
    try std.testing.expectError(error.InvalidDate, parseFindBoundaryMillis("2026-13-01", .since));
    try std.testing.expectError(error.InvalidDate, parseFindBoundaryMillis("2026-04-31", .since));
    try std.testing.expectError(error.InvalidDate, parseFindBoundaryMillis("2026/03/11", .since));
    try std.testing.expectError(error.InvalidDate, parseFindBoundaryMillis("2026-03-11T12:34:56Z", .since));
}

test "parseFindBoundaryMillis rejects nonexistent local datetime" {
    const allocator = std.testing.allocator;
    const previous = std.process.getEnvVarOwned(allocator, "TZ") catch null;
    defer if (previous) |value| allocator.free(value);
    defer {
        if (previous) |value| {
            if (allocator.dupeZ(u8, value)) |value_z| {
                defer allocator.free(value_z);
                _ = c.setenv("TZ", value_z.ptr, 1);
            } else |_| {
                _ = c.unsetenv("TZ");
            }
        } else {
            _ = c.unsetenv("TZ");
        }
        c.tzset();
    }

    try std.testing.expectEqual(@as(c_int, 0), c.setenv("TZ", "America/Los_Angeles", 1));
    c.tzset();
    try std.testing.expectError(error.InvalidDate, parseFindBoundaryMillis("2026-03-08T02:30:00", .since));
}

test "parseFindBoundaryMillis rejects ambiguous local datetime" {
    const allocator = std.testing.allocator;
    const previous = std.process.getEnvVarOwned(allocator, "TZ") catch null;
    defer if (previous) |value| allocator.free(value);
    defer {
        if (previous) |value| {
            if (allocator.dupeZ(u8, value)) |value_z| {
                defer allocator.free(value_z);
                _ = c.setenv("TZ", value_z.ptr, 1);
            } else |_| {
                _ = c.unsetenv("TZ");
            }
        } else {
            _ = c.unsetenv("TZ");
        }
        c.tzset();
    }

    try std.testing.expectEqual(@as(c_int, 0), c.setenv("TZ", "America/Los_Angeles", 1));
    c.tzset();
    try std.testing.expectError(error.InvalidDate, parseFindBoundaryMillis("2026-11-01T01:30:00", .since));
}
