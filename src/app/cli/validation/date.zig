const std = @import("std");

// Validates a `YYYY-MM-DD` date string and rejects impossible calendar dates.
pub fn validateDateYmd(raw: []const u8) !void {
    if (raw.len != 10) return error.InvalidDate;
    if (raw[4] != '-' or raw[7] != '-') return error.InvalidDate;

    var idx: usize = 0;
    while (idx < raw.len) : (idx += 1) {
        if (idx == 4 or idx == 7) continue;
        if (!std.ascii.isDigit(raw[idx])) return error.InvalidDate;
    }

    const year = try parse2to4(raw[0..4]);
    const month = try parse2to4(raw[5..7]);
    const day = try parse2to4(raw[8..10]);

    if (month < 1 or month > 12) return error.InvalidDate;
    if (day < 1 or day > daysInMonth(year, month)) return error.InvalidDate;
}

// Parses a short ASCII digit slice into a `u16` date component.
fn parse2to4(slice: []const u8) !u16 {
    var value: u16 = 0;
    for (slice) |ch| {
        if (!std.ascii.isDigit(ch)) return error.InvalidDate;
        value = value * 10 + @as(u16, ch - '0');
    }
    return value;
}

// Reports whether the Gregorian year is a leap year.
fn isLeapYear(year: u16) bool {
    if (year % 4 != 0) return false;
    if (year % 100 != 0) return true;
    return year % 400 == 0;
}

// Returns the number of days in the given month for the given year.
fn daysInMonth(year: u16, month: u16) u16 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

test "validateDateYmd accepts valid calendar dates" {
    try validateDateYmd("2026-03-11");
    try validateDateYmd("2024-02-29");
}

test "validateDateYmd rejects impossible dates" {
    try std.testing.expectError(error.InvalidDate, validateDateYmd("2026-02-29"));
    try std.testing.expectError(error.InvalidDate, validateDateYmd("2026-02-30"));
    try std.testing.expectError(error.InvalidDate, validateDateYmd("2026-13-01"));
    try std.testing.expectError(error.InvalidDate, validateDateYmd("2026-00-01"));
    try std.testing.expectError(error.InvalidDate, validateDateYmd("2026-04-31"));
}
