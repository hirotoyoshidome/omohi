const std = @import("std");

const c = @cImport({
    @cInclude("time.h");
});

pub const LocalTimestampError = error{
    TimestampBeforeEpoch,
    TimestampOutOfRange,
    LocaltimeFailed,
};

/// Formats epoch millis into local ISO-8601 with milliseconds and numeric offset.
/// Example: YYYY-MM-DDTHH:MM:SS.mmm+09:00
pub fn iso8601FromMillisLocal(millis: i64) LocalTimestampError![29]u8 {
    if (millis < 0) return error.TimestampBeforeEpoch;

    const seconds: i64 = @divTrunc(millis, std.time.ms_per_s);
    const millisecond: u16 = @intCast(@mod(millis, std.time.ms_per_s));
    if (seconds < 0) return error.TimestampBeforeEpoch;

    var timer: c.time_t = std.math.cast(c.time_t, seconds) orelse return error.TimestampOutOfRange;
    var local_tm: c.struct_tm = undefined;
    if (c.localtime_r(&timer, &local_tm) == null) return error.LocaltimeFailed;

    const year_i32 = local_tm.tm_year + 1900;
    const month_i32 = local_tm.tm_mon + 1;
    const day_i32 = local_tm.tm_mday;
    const hour_i32 = local_tm.tm_hour;
    const minute_i32 = local_tm.tm_min;
    const second_i32 = local_tm.tm_sec;

    if (year_i32 < 0 or year_i32 > 9999) return error.LocaltimeFailed;
    if (month_i32 < 1 or month_i32 > 12) return error.LocaltimeFailed;
    if (day_i32 < 1 or day_i32 > 31) return error.LocaltimeFailed;
    if (hour_i32 < 0 or hour_i32 > 23) return error.LocaltimeFailed;
    if (minute_i32 < 0 or minute_i32 > 59) return error.LocaltimeFailed;
    if (second_i32 < 0 or second_i32 > 60) return error.LocaltimeFailed;

    const offset_seconds: i64 = @intCast(local_tm.tm_gmtoff);
    const sign: u8 = if (offset_seconds >= 0) '+' else '-';
    const offset_abs: i64 = if (offset_seconds < 0) -offset_seconds else offset_seconds;
    const offset_minutes_total: i64 = @divTrunc(offset_abs, 60);
    const offset_hours: u8 = @intCast(@divTrunc(offset_minutes_total, 60));
    const offset_minutes: u8 = @intCast(@mod(offset_minutes_total, 60));

    var formatted: [29]u8 = undefined;
    _ = std.fmt.bufPrint(
        &formatted,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}{c}{d:0>2}:{d:0>2}",
        .{
            @as(u16, @intCast(year_i32)),
            @as(u8, @intCast(month_i32)),
            @as(u8, @intCast(day_i32)),
            @as(u8, @intCast(hour_i32)),
            @as(u8, @intCast(minute_i32)),
            @as(u8, @intCast(second_i32)),
            millisecond,
            sign,
            offset_hours,
            offset_minutes,
        },
    ) catch return error.LocaltimeFailed;

    return formatted;
}

test "iso8601FromMillisLocal keeps fixed shape" {
    const value = try iso8601FromMillisLocal(0);
    try std.testing.expectEqual(@as(usize, 29), value.len);
    try std.testing.expect(value[4] == '-');
    try std.testing.expect(value[7] == '-');
    try std.testing.expect(value[10] == 'T');
    try std.testing.expect(value[13] == ':');
    try std.testing.expect(value[16] == ':');
    try std.testing.expect(value[19] == '.');
    try std.testing.expect(value[26] == ':');
}
