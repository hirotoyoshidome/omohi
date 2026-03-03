const std = @import("std");

pub const OmohiLocation = struct {
    path: []u8,
    dir: std.fs.Dir,

    pub fn deinit(self: *OmohiLocation, allocator: std.mem.Allocator) void {
        self.dir.close();
        allocator.free(self.path);
    }
};

pub fn resolveOmohiPath(allocator: std.mem.Allocator) ![]u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return error.MissingHome;
    defer allocator.free(home);

    return std.fmt.allocPrint(allocator, "{s}/.omohi", .{home});
}

pub fn openOmohiDir(
    allocator: std.mem.Allocator,
    create_if_missing: bool,
) !OmohiLocation {
    const omohi_path = try resolveOmohiPath(allocator);
    errdefer allocator.free(omohi_path);

    if (create_if_missing) {
        try std.fs.cwd().makePath(omohi_path);
    }

    const dir = std.fs.cwd().openDir(omohi_path, .{ .iterate = true, .access_sub_paths = true }) catch |err| switch (err) {
        error.FileNotFound => return error.OmohiNotInitialized,
        else => return err,
    };

    return .{ .path = omohi_path, .dir = dir };
}
