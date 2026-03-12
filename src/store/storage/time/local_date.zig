const std = @import("std");

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("time.h");
});

pub const TimestampParseError = error{
    InvalidTimestamp,
    TimestampBeforeEpoch,
    TimestampOutOfRange,
};

pub const LocalDateError = TimestampParseError || error{
    LocaltimeFailed,
};

/// Parses UTC ISO-8601 timestamp (`YYYY-MM-DDTHH:MM:SS.mmmZ`) into epoch milliseconds.
/// Memory: borrowed
pub fn parseUtcIso8601Millis(raw: []const u8) TimestampParseError!i64 {
    if (raw.len != 24) return error.InvalidTimestamp;
    if (raw[4] != '-' or raw[7] != '-' or raw[10] != 'T' or raw[13] != ':' or raw[16] != ':' or raw[19] != '.' or raw[23] != 'Z') {
        return error.InvalidTimestamp;
    }

    const year = try parseInt(raw[0..4]);
    const month = try parseInt(raw[5..7]);
    const day = try parseInt(raw[8..10]);
    const hour = try parseInt(raw[11..13]);
    const minute = try parseInt(raw[14..16]);
    const second = try parseInt(raw[17..19]);
    const millisecond = try parseInt(raw[20..23]);

    if (month < 1 or month > 12) return error.InvalidTimestamp;
    if (day < 1 or day > daysInMonth(year, month)) return error.InvalidTimestamp;
    if (hour < 0 or hour > 23) return error.InvalidTimestamp;
    if (minute < 0 or minute > 59) return error.InvalidTimestamp;
    if (second < 0 or second > 59) return error.InvalidTimestamp;
    if (millisecond < 0 or millisecond > 999) return error.InvalidTimestamp;

    const epoch_days = daysFromCivil(year, month, day);
    if (epoch_days < 0) return error.TimestampBeforeEpoch;

    const sec_per_day: i64 = 86_400;
    const seconds =
        try mulI64(epoch_days, sec_per_day) +
        try mulI64(hour, 3600) +
        try mulI64(minute, 60) +
        second;
    const millis = try mulI64(seconds, 1000) + millisecond;
    return millis;
}

/// Converts UTC ISO-8601 timestamp (`YYYY-MM-DDTHH:MM:SS.mmmZ`) into local date (`YYYY-MM-DD`).
/// Memory: value type `[10]u8`.
pub fn utcIso8601ToLocalYmd(utc_iso: []const u8) LocalDateError![10]u8 {
    const millis = try parseUtcIso8601Millis(utc_iso);
    const seconds: i64 = @divTrunc(millis, 1000);
    if (seconds < 0) return error.TimestampBeforeEpoch;

    var timer: c.time_t = std.math.cast(c.time_t, seconds) orelse return error.TimestampOutOfRange;
    var local_tm: c.struct_tm = undefined;
    if (c.localtime_r(&timer, &local_tm) == null) return error.LocaltimeFailed;

    const year_i32 = local_tm.tm_year + 1900;
    const month_i32 = local_tm.tm_mon + 1;
    const day_i32 = local_tm.tm_mday;
    if (year_i32 < 0 or year_i32 > 9999) return error.LocaltimeFailed;
    if (month_i32 < 1 or month_i32 > 12) return error.LocaltimeFailed;
    if (day_i32 < 1 or day_i32 > 31) return error.LocaltimeFailed;

    var formatted: [32]u8 = undefined;
    const out_slice = std.fmt.bufPrint(
        &formatted,
        "{d:0>4}-{d:0>2}-{d:0>2}",
        .{
            @as(u16, @intCast(year_i32)),
            @as(u8, @intCast(month_i32)),
            @as(u8, @intCast(day_i32)),
        },
    ) catch return error.LocaltimeFailed;

    if (out_slice.len != 10) return error.LocaltimeFailed;
    var out: [10]u8 = undefined;
    @memcpy(&out, out_slice[0..10]);
    return out;
}

fn parseInt(slice: []const u8) TimestampParseError!i64 {
    var value: i64 = 0;
    for (slice) |ch| {
        if (!std.ascii.isDigit(ch)) return error.InvalidTimestamp;
        const digit = @as(i64, @intCast(ch - '0'));
        value = try mulI64(value, 10);
        value += digit;
    }
    return value;
}

fn isLeapYear(year: i64) bool {
    if (@mod(year, 4) != 0) return false;
    if (@mod(year, 100) != 0) return true;
    return @mod(year, 400) == 0;
}

fn daysInMonth(year: i64, month: i64) i64 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

fn daysFromCivil(year: i64, month: i64, day: i64) i64 {
    var y = year;
    if (month <= 2) y -= 1;

    const era = @divFloor(y, 400);
    const yoe = y - era * 400;
    const shifted_month = month + (if (month > 2) @as(i64, -3) else @as(i64, 9));
    const doy = @divFloor(153 * shifted_month + 2, 5) + day - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;

    return era * 146097 + doe - 719468;
}

fn mulI64(a: i64, b: i64) TimestampParseError!i64 {
    return std.math.mul(i64, a, b) catch error.TimestampOutOfRange;
}

test "parseUtcIso8601Millis parses epoch" {
    try std.testing.expectEqual(@as(i64, 0), try parseUtcIso8601Millis("1970-01-01T00:00:00.000Z"));
}

test "parseUtcIso8601Millis rejects malformed timestamp" {
    try std.testing.expectError(error.InvalidTimestamp, parseUtcIso8601Millis("2026-03-01"));
    try std.testing.expectError(error.InvalidTimestamp, parseUtcIso8601Millis("2026-02-30T00:00:00.000Z"));
}

test "utcIso8601ToLocalYmd respects timezone via libc localtime" {
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

    try std.testing.expectEqual(@as(c_int, 0), c.setenv("TZ", "Asia/Tokyo", 1));
    c.tzset();

    const local_day = try utcIso8601ToLocalYmd("2026-03-10T18:00:00.000Z");
    try std.testing.expectEqualStrings("2026-03-11", &local_day);
}
