const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("types.zig");
const track = @import("../command/track.zig");
const untrack = @import("../command/untrack.zig");
const add = @import("../command/add.zig");
const rm = @import("../command/rm.zig");
const commit = @import("../command/commit.zig");
const status = @import("../command/status.zig");
const tracklist = @import("../command/tracklist.zig");
const find = @import("../command/find.zig");
const show = @import("../command/show.zig");
const tag_ls = @import("../command/tag_ls.zig");
const tag_add = @import("../command/tag_add.zig");
const tag_rm = @import("../command/tag_rm.zig");
const help = @import("../command/help.zig");

pub fn dispatch(allocator: std.mem.Allocator, parsed: parser_types.ParsedRequest) !command_types.CommandResult {
    return switch (parsed) {
        .track => |args| try track.run(allocator, args),
        .untrack => |args| try untrack.run(allocator, args),
        .add => |args| try add.run(allocator, args),
        .rm => |args| try rm.run(allocator, args),
        .commit => |args| try commit.run(allocator, args),
        .status => try status.run(allocator),
        .tracklist => try tracklist.run(allocator),
        .find => |args| try find.run(allocator, args),
        .show => |args| try show.run(allocator, args),
        .tag_ls => |args| try tag_ls.run(allocator, args),
        .tag_add => |args| try tag_add.run(allocator, args),
        .tag_rm => |args| try tag_rm.run(allocator, args),
        .help => try help.run(allocator),
    };
}
