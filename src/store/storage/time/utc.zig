const std = @import("std");
const testing = std.testing;

/// Errors for timestamp formatting.
pub const TimestampError = error{
    TimestampBeforeEpoch,
};

/// Returns current UTC timestamp in ISO-8601 format with milliseconds precision.
/// Memory: value type `[24]u8`.
pub fn nowIso8601Utc() TimestampError![24]u8 {
    return iso8601FromMillis(std.time.milliTimestamp());
}

/// Formats the given UTC milliseconds-since-epoch into ISO-8601.
/// Memory: value type `[24]u8`.
pub fn iso8601FromMillis(millis: i64) TimestampError![24]u8 {
    if (millis < 0) return error.TimestampBeforeEpoch;

    const ms_per_s_i64 = @as(i64, std.time.ms_per_s);
    const seconds = @divTrunc(millis, ms_per_s_i64);
    const remainder = @mod(millis, ms_per_s_i64);

    var buffer: [24]u8 = undefined;
    const epoch_seconds = std.time.epoch.EpochSeconds{
        .secs = @as(u64, @intCast(seconds)),
    };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    const year = year_day.year;
    const month = month_day.month.numeric();
    const day = @as(u8, @intCast(month_day.day_index + 1));
    const hour = day_seconds.getHoursIntoDay();
    const minute = day_seconds.getMinutesIntoHour();
    const second = day_seconds.getSecondsIntoMinute();
    const milli = @as(u16, @intCast(remainder));

    _ = std.fmt.bufPrint(
        &buffer,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z",
        .{ year, month, day, hour, minute, second, milli },
    ) catch unreachable;

    return buffer;
}

test "iso8601FromMillis formats epoch start" {
    const result = try iso8601FromMillis(0);
    try testing.expectEqualStrings("1970-01-01T00:00:00.000Z", &result);
}
