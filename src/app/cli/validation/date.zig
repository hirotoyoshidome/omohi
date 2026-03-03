const std = @import("std");

pub fn validateDateYmd(raw: []const u8) !void {
    if (raw.len != 10) return error.InvalidDate;
    if (raw[4] != '-' or raw[7] != '-') return error.InvalidDate;

    var idx: usize = 0;
    while (idx < raw.len) : (idx += 1) {
        if (idx == 4 or idx == 7) continue;
        if (!std.ascii.isDigit(raw[idx])) return error.InvalidDate;
    }
}
