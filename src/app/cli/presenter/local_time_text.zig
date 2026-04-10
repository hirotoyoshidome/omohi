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

/// Converts a UTC ISO-8601 timestamp into owned local time text and falls back to the input on parse failure.
pub fn dupeLocalTimestampOrOriginal(allocator: std.mem.Allocator, utc_iso: []const u8) ![]u8 {
    const millis = parseUtcIso8601Millis(utc_iso) catch return allocator.dupe(u8, utc_iso);
    const local = iso8601FromMillisLocal(millis) catch return allocator.dupe(u8, utc_iso);
    return allocator.dupe(u8, local[0..]);
}

// Parses UTC ISO-8601 text (`YYYY-MM-DDTHH:MM:SS.mmmZ`) into epoch milliseconds.
fn parseUtcIso8601Millis(raw: []const u8) TimestampParseError!i64 {
    if (raw.len != 24) return error.InvalidTimestamp;
    if (raw[4] != '-' or raw[7] != '-' or raw[10] != 'T' or raw[13] != ':' or raw[16] != ':' or raw[19] != '.' or raw[23] != 'Z') {
        return error.InvalidTimestamp;
    }

    const year = try parseTimestampInt(raw[0..4]);
    const month = try parseTimestampInt(raw[5..7]);
    const day = try parseTimestampInt(raw[8..10]);
    const hour = try parseTimestampInt(raw[11..13]);
    const minute = try parseTimestampInt(raw[14..16]);
    const second = try parseTimestampInt(raw[17..19]);
    const millisecond = try parseTimestampInt(raw[20..23]);

    if (month < 1 or month > 12) return error.InvalidTimestamp;
    if (day < 1 or day > daysInMonth(year, month)) return error.InvalidTimestamp;
    if (hour < 0 or hour > 23) return error.InvalidTimestamp;
    if (minute < 0 or minute > 59) return error.InvalidTimestamp;
    if (second < 0 or second > 59) return error.InvalidTimestamp;
    if (millisecond < 0 or millisecond > 999) return error.InvalidTimestamp;

    const epoch_days = daysFromCivil(year, month, day);
    if (epoch_days < 0) return error.TimestampBeforeEpoch;

    const seconds =
        try mulI64(epoch_days, 86_400) +
        try mulI64(hour, 3600) +
        try mulI64(minute, 60) +
        second;
    return try mulI64(seconds, 1000) + millisecond;
}

// Formats epoch milliseconds into local ISO-8601 with milliseconds and numeric offset.
fn iso8601FromMillisLocal(millis: i64) error{ TimestampBeforeEpoch, TimestampOutOfRange, LocaltimeFailed }![29]u8 {
    if (millis < 0) return error.TimestampBeforeEpoch;

    const seconds: i64 = @divTrunc(millis, std.time.ms_per_s);
    const millisecond: u16 = @intCast(@mod(millis, std.time.ms_per_s));
    var timer: c.time_t = std.math.cast(c.time_t, seconds) orelse return error.TimestampOutOfRange;
    var local_tm: c.struct_tm = undefined;
    if (c.localtime_r(&timer, &local_tm) == null) return error.LocaltimeFailed;

    const offset_seconds: i64 = @intCast(local_tm.tm_gmtoff);
    const sign: u8 = if (offset_seconds >= 0) '+' else '-';
    const offset_abs: i64 = if (offset_seconds < 0) -offset_seconds else offset_seconds;
    const offset_minutes_total: i64 = @divTrunc(offset_abs, 60);

    var formatted: [29]u8 = undefined;
    _ = std.fmt.bufPrint(
        &formatted,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}{c}{d:0>2}:{d:0>2}",
        .{
            @as(u16, @intCast(local_tm.tm_year + 1900)),
            @as(u8, @intCast(local_tm.tm_mon + 1)),
            @as(u8, @intCast(local_tm.tm_mday)),
            @as(u8, @intCast(local_tm.tm_hour)),
            @as(u8, @intCast(local_tm.tm_min)),
            @as(u8, @intCast(local_tm.tm_sec)),
            millisecond,
            sign,
            @as(u8, @intCast(@divTrunc(offset_minutes_total, 60))),
            @as(u8, @intCast(@mod(offset_minutes_total, 60))),
        },
    ) catch return error.LocaltimeFailed;

    return formatted;
}

// Parses an ASCII digit slice into a signed integer timestamp component.
fn parseTimestampInt(slice: []const u8) TimestampParseError!i64 {
    var value: i64 = 0;
    for (slice) |ch| {
        if (!std.ascii.isDigit(ch)) return error.InvalidTimestamp;
        value = try mulI64(value, 10);
        value += @as(i64, @intCast(ch - '0'));
    }
    return value;
}

// Reports whether the Gregorian year is a leap year.
fn isLeapYear(year: i64) bool {
    if (@mod(year, 4) != 0) return false;
    if (@mod(year, 100) != 0) return true;
    return @mod(year, 400) == 0;
}

// Returns the number of days in the given month for the given year.
fn daysInMonth(year: i64, month: i64) i64 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

// Converts a civil date to days since the Unix epoch.
fn daysFromCivil(year: i64, month: i64, day: i64) i64 {
    var y = year;
    var m = month;
    y -= if (m <= 2) 1 else 0;
    const era = @divFloor(y, 400);
    const yoe = y - era * 400;
    m += if (m > 2) -3 else 9;
    const doy = @divFloor(153 * m + 2, 5) + day - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146_097 + doe - 719_468;
}

// Multiplies i64 values while preserving overflow as timestamp-range failure.
fn mulI64(lhs: i64, rhs: i64) TimestampParseError!i64 {
    return std.math.mul(i64, lhs, rhs) catch error.TimestampOutOfRange;
}

pub const TimezoneGuard = struct {
    previous: ?[]u8,

    // TEST-ONLY: Restores the previous `TZ` value and releases owned storage.
    pub fn deinit(self: *TimezoneGuard, allocator: std.mem.Allocator) void {
        if (self.previous) |value| {
            const value_z = allocator.dupeZ(u8, value) catch {
                allocator.free(value);
                self.previous = null;
                _ = c.unsetenv("TZ");
                c.tzset();
                return;
            };
            defer allocator.free(value_z);
            _ = c.setenv("TZ", value_z.ptr, 1);
            allocator.free(value);
        } else {
            _ = c.unsetenv("TZ");
        }
        self.previous = null;
        c.tzset();
    }
};

// TEST-ONLY: Sets `TZ` for a test and returns a guard that restores the previous value.
pub fn initTimezoneGuard(allocator: std.mem.Allocator, tz_name: []const u8) !TimezoneGuard {
    const previous = std.process.getEnvVarOwned(allocator, "TZ") catch null;
    const tz_name_z = try allocator.dupeZ(u8, tz_name);
    defer allocator.free(tz_name_z);

    try std.testing.expectEqual(@as(c_int, 0), c.setenv("TZ", tz_name_z.ptr, 1));
    c.tzset();

    return .{ .previous = previous };
}

test "dupeLocalTimestampOrOriginal converts UTC to local text" {
    var tz_guard = try initTimezoneGuard(std.testing.allocator, "Asia/Tokyo");
    defer tz_guard.deinit(std.testing.allocator);

    const output = try dupeLocalTimestampOrOriginal(std.testing.allocator, "2026-04-01T12:27:39.914Z");
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("2026-04-01T21:27:39.914+09:00", output);
}

test "dupeLocalTimestampOrOriginal falls back to the original text on parse failure" {
    const output = try dupeLocalTimestampOrOriginal(std.testing.allocator, "not-a-timestamp");
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("not-a-timestamp", output);
}
