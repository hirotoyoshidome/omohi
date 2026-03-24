const std = @import("std");
const command_catalog = @import("../command_catalog.zig");
const exit_code = @import("../error/exit_code.zig");

pub fn renderCliMan(allocator: std.mem.Allocator) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.writeAll(".TH OMOHI 1 \"\" \"omohi\" \"omohi Manual\"\n");
    try writer.writeAll(".SH NAME\n");
    try writer.writeAll("omohi \\- local-first CLI for process logging\n");
    try writer.writeAll(".SH SYNOPSIS\n");
    try writer.writeAll(".B omohi\n");
    try writer.writeAll(".RI command \" [arguments]\"\n");
    try writer.writeAll(".SH DESCRIPTION\n");
    try writer.writeAll("omohi separates tracking, recording, and referencing so process history remains durable local data.\n");
    try writer.writeAll(".PP\n");
    try writer.writeAll("This page is generated from ");
    try writeEscaped(writer, "src/app/cli/command_catalog.zig");
    try writer.writeAll(". Do not edit manually.\n");
    try writer.writeAll(".SH COMMANDS\n");

    for (command_catalog.all) |spec| {
        try writer.writeAll(".SS ");
        try writeEscaped(writer, spec.name);
        try writer.writeByte('\n');

        try writeLabelledText(writer, "Summary", spec.summary);
        try writePreformattedBlock(writer, "Usage", spec.usage);

        if (spec.positionals.len > 0) {
            try writer.writeAll(".TP\n");
            try writer.writeAll(".B Positionals\n");
            for (spec.positionals) |arg| {
                const requirement = if (arg.required) "required" else "optional";
                const repeatable = if (arg.repeatable) ", repeatable" else "";
                try writer.writeAll(".RS 4\n");
                try writer.writeAll(".B ");
                try writeEscaped(writer, arg.name);
                try writer.writeByte('\n');
                try writeEscaped(writer, requirement);
                try writeEscaped(writer, repeatable);
                try writer.writeAll(": ");
                try writeEscaped(writer, arg.description);
                try writer.writeByte('\n');
                try writer.writeAll(".RE\n");
            }
        }

        if (spec.options.len > 0) {
            try writer.writeAll(".TP\n");
            try writer.writeAll(".B Options\n");
            for (spec.options) |opt| {
                try writer.writeAll(".RS 4\n");
                try writeOptionNames(writer, opt);
                try writer.writeByte('\n');
                try writeEscaped(writer, if (opt.required) "required" else "optional");
                if (opt.repeatable) {
                    try writer.writeAll(", repeatable");
                }
                try writer.writeAll(": ");
                try writeEscaped(writer, opt.description);
                try writer.writeByte('\n');
                try writer.writeAll(".RE\n");
            }
        }

        if (spec.examples.len > 0) {
            try writeExamples(writer, spec.examples);
        }

        if (spec.notes.len > 0) {
            try writer.writeAll(".TP\n");
            try writer.writeAll(".B Notes\n");
            for (spec.notes) |note| {
                try writer.writeAll(".RS 4\n");
                try writeEscaped(writer, note);
                try writer.writeByte('\n');
                try writer.writeAll(".RE\n");
            }
        }
    }

    try writer.writeAll(".SH EXIT STATUS\n");
    try writeExitCode(writer, exit_code.ok, "success");
    try writeExitCode(writer, exit_code.usage_error, "CLI usage error");
    try writeExitCode(writer, exit_code.domain_error, "domain error");
    try writeExitCode(writer, exit_code.use_case_error, "use-case error");
    try writeExitCode(writer, exit_code.system_error, "system error");
    try writeExitCode(writer, exit_code.data_destroyed, "data destroyed (reserved)");

    try writer.writeAll(".SH FILES\n");
    try writer.writeAll(".TP\n");
    try writer.writeAll(".I ~/.omohi\n");
    try writer.writeAll("Single-user local store root.\n");

    try writer.writeAll(".SH SEE ALSO\n");
    try writer.writeAll(".BR omohi (1)\n");

    return out.toOwnedSlice();
}

fn writeLabelledText(writer: anytype, label: []const u8, text: []const u8) !void {
    try writer.writeAll(".TP\n");
    try writer.writeAll(".B ");
    try writeEscaped(writer, label);
    try writer.writeByte('\n');
    try writeEscaped(writer, text);
    try writer.writeByte('\n');
}

fn writePreformattedBlock(writer: anytype, label: []const u8, usage: []const u8) !void {
    try writer.writeAll(".TP\n");
    try writer.writeAll(".B ");
    try writeEscaped(writer, label);
    try writer.writeByte('\n');
    try writer.writeAll(".nf\n");
    try writeEscaped(writer, "omohi ");
    try writeEscaped(writer, usage);
    try writer.writeByte('\n');
    try writer.writeAll(".fi\n");
}

fn writeExamples(writer: anytype, examples: []const []const u8) !void {
    try writer.writeAll(".TP\n");
    try writer.writeAll(".B Examples\n");
    try writer.writeAll(".nf\n");
    for (examples) |example| {
        try writeEscaped(writer, example);
        try writer.writeByte('\n');
    }
    try writer.writeAll(".fi\n");
}

fn writeOptionNames(writer: anytype, opt: command_catalog.OptionArgSpec) !void {
    try writer.writeAll(".B ");
    if (opt.short) |short_opt| {
        try writeEscaped(writer, "-");
        try writer.writeByte(short_opt);
        if (opt.long.len > 0) {
            try writer.writeAll(", ");
        }
    }
    if (opt.long.len > 0) {
        try writeEscaped(writer, "--");
        try writeEscaped(writer, opt.long);
    }
    if (opt.value_name) |value_name| {
        try writer.writeByte(' ');
        try writeEscaped(writer, "<");
        try writeEscaped(writer, value_name);
        try writeEscaped(writer, ">");
    }
}

fn writeExitCode(writer: anytype, code: u8, description: []const u8) !void {
    try writer.writeAll(".TP\n");
    try writer.print(".B {d}\n", .{code});
    try writeEscaped(writer, description);
    try writer.writeByte('\n');
}

fn writeEscaped(writer: anytype, text: []const u8) !void {
    for (text, 0..) |char, idx| {
        switch (char) {
            '\\' => try writer.writeAll("\\e"),
            '-' => try writer.writeAll("\\-"),
            '.' => {
                if (idx == 0) {
                    try writer.writeAll("\\&.");
                } else {
                    try writer.writeByte('.');
                }
            },
            '\'' => {
                if (idx == 0) {
                    try writer.writeAll("\\&'");
                } else {
                    try writer.writeByte('\'');
                }
            },
            else => try writer.writeByte(char),
        }
    }
}

test "renderCliMan includes main sections and commands" {
    const rendered = try renderCliMan(std.testing.allocator);
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, ".TH OMOHI 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, ".SH COMMANDS") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, ".SS commit") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, ".SH EXIT STATUS") != null);
}

test "renderCliMan escapes hyphenated options and content" {
    const rendered = try renderCliMan(std.testing.allocator);
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "\\-\\-dry\\-run") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, ".B 10\nsystem error") != null);
}
