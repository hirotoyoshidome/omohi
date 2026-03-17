const std = @import("std");
const command_catalog = @import("../command_catalog.zig");
const exit_code = @import("../error/exit_code.zig");
const error_message = @import("../error/error_message.zig");

pub fn renderCliMarkdown(allocator: std.mem.Allocator) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.writeAll("# omohi CLI Reference\n\n");
    try writer.writeAll("This file is generated from `src/app/cli/command_catalog.zig`. Do not edit manually.\n\n");

    try writer.writeAll("## Command Summary\n\n");
    try writer.writeAll("| Command | Usage | Summary |\n");
    try writer.writeAll("| --- | --- | --- |\n");
    for (command_catalog.all) |spec| {
        try writer.print("| `{s}` | `{s}` | {s} |\n", .{ spec.name, spec.usage, spec.summary });
    }

    try writer.writeAll("\n## Command Details\n\n");
    for (command_catalog.all) |spec| {
        try writer.print("### {s}\n\n", .{spec.name});
        try writer.print("- Usage: `omohi {s}`\n", .{spec.usage});
        try writer.print("- Summary: {s}\n", .{spec.summary});

        try writer.writeAll("- Positionals:\n");
        if (spec.positionals.len == 0) {
            try writer.writeAll("  - None\n");
        } else {
            for (spec.positionals) |arg| {
                const requirement = if (arg.required) "required" else "optional";
                const repeatable = if (arg.repeatable) ", repeatable" else "";
                try writer.print("  - `{s}` ({s}{s}): {s}\n", .{ arg.name, requirement, repeatable, arg.description });
            }
        }

        try writer.writeAll("- Options:\n");
        if (spec.options.len == 0) {
            try writer.writeAll("  - None\n");
        } else {
            for (spec.options) |opt| {
                var names = std.array_list.Managed(u8).init(allocator);
                defer names.deinit();
                const names_writer = names.writer();
                if (opt.short) |short_opt| {
                    try names_writer.print("`-{c}`", .{short_opt});
                    if (opt.long.len > 0) try names_writer.writeAll(", ");
                }
                if (opt.long.len > 0) {
                    try names_writer.print("`--{s}`", .{opt.long});
                }
                if (opt.value_name) |value_name| {
                    try names_writer.print(" `<{s}>`", .{value_name});
                }

                const requirement = if (opt.required) "required" else "optional";
                const repeatable = if (opt.repeatable) ", repeatable" else "";
                try writer.print("  - {s} ({s}{s}): {s}\n", .{ names.items, requirement, repeatable, opt.description });
            }
        }

        try writer.writeAll("- Examples:\n");
        if (spec.examples.len == 0) {
            try writer.writeAll("  - None\n");
        } else {
            for (spec.examples) |example| {
                try writer.print("  - `{s}`\n", .{example});
            }
        }

        try writer.writeAll("- Notes:\n");
        if (spec.notes.len == 0) {
            try writer.writeAll("  - None\n\n");
        } else {
            for (spec.notes) |note| {
                try writer.print("  - {s}\n", .{note});
            }
            try writer.writeAll("\n");
        }
    }

    try writer.writeAll("## Exit Codes\n\n");
    try writer.print("- `0`: success\n", .{});
    try writer.print("- `{d}`: CLI usage error\n", .{exit_code.usage_error});
    try writer.print("- `{d}`: domain error\n", .{exit_code.domain_error});
    try writer.print("- `{d}`: use-case error\n", .{exit_code.use_case_error});
    try writer.print("- `{d}`: system error\n", .{exit_code.system_error});
    try writer.print("- `{d}`: data destroyed (reserved)\n\n", .{exit_code.data_destroyed});

    try writer.writeAll("## Representative Errors\n\n");
    try writer.print("- Parse `InvalidCommand`: {s}\n", .{error_message.forParseError(error.InvalidCommand)});
    try writer.print("- Parse `MissingArgument`: {s}\n", .{error_message.forParseError(error.MissingArgument)});
    try writer.print("- Parse `UnknownOption`: {s}\n", .{error_message.forParseError(error.UnknownOption)});
    try writer.print("- Parse `InvalidDate`: {s}\n", .{error_message.forParseError(error.InvalidDate)});
    try writer.print("- Runtime `NothingToCommit`: {s}\n", .{error_message.forRuntimeError(error.NothingToCommit)});
    try writer.print("- Runtime `OmohiNotInitialized`: {s}\n", .{error_message.forRuntimeError(error.OmohiNotInitialized)});
    try writer.print("- Runtime `CommitNotFound`: {s}\n", .{error_message.forRuntimeError(error.CommitNotFound)});
    try writer.print("- Runtime `NotFound`: {s}\n", .{error_message.forRuntimeError(error.NotFound)});
    try writer.print("- Runtime `AlreadyTracked`: {s}\n", .{error_message.forRuntimeError(error.AlreadyTracked)});
    try writer.print("- Runtime `LockAlreadyAcquired`: {s}\n", .{error_message.forRuntimeError(error.LockAlreadyAcquired)});
    try writer.print("- Runtime `VersionMismatch`: {s}\n", .{error_message.forRuntimeError(error.VersionMismatch)});
    try writer.print("- Runtime `MissingStoreVersion`: {s}\n", .{error_message.forRuntimeError(error.MissingStoreVersion)});

    return out.toOwnedSlice();
}

test "renderCliMarkdown includes key sections and commands" {
    const rendered = try renderCliMarkdown(std.testing.allocator);
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "# omohi CLI Reference") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "## Command Summary") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "### commit") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "## Exit Codes") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "## Representative Errors") != null);
}
