const std = @import("std");
const layer_import_guard = @import("contracts/layer_import_guard.zig");

pub fn build(b: *std.Build) void {
    layer_import_guard.runCheck(b.allocator) catch |err| {
        std.debug.panic("layer import contract check failed: {s}", .{@errorName(err)});
    };

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const app_version = resolveAppVersion(b);

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "app_version", app_version);

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    exe_module.addOptions("build_options", build_options);

    const exe = b.addExecutable(.{
        .name = "omohi",
        .root_module = exe_module,
    });
    b.installArtifact(exe);

    // zig build run
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // zig build docs-cli
    const docs_module = b.createModule(.{
        .root_source_file = b.path("src/app/cli/generate_cli_docs.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const docs_exe = b.addExecutable(.{
        .name = "generate-cli-docs",
        .root_module = docs_module,
    });
    const run_docs = b.addRunArtifact(docs_exe);
    const docs_step = b.step("docs-cli", "Generate CLI markdown documentation");
    docs_step.dependOn(&run_docs.step);

    // zig build docs-man
    const man_module = b.createModule(.{
        .root_source_file = b.path("src/app/cli/generate_cli_man.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const man_exe = b.addExecutable(.{
        .name = "generate-cli-man",
        .root_module = man_module,
    });
    const run_man = b.addRunArtifact(man_exe);
    const man_step = b.step("docs-man", "Generate CLI man page");
    man_step.dependOn(&run_man.step);

    const all_docs_step = b.step("docs", "Generate CLI markdown and man documentation");
    all_docs_step.dependOn(&run_docs.step);
    all_docs_step.dependOn(&run_man.step);

    // zig build test
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_module.addOptions("build_options", build_options);

    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

fn resolveAppVersion(b: *std.Build) []const u8 {
    const fallback = "0.0.0-dev";

    const result = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "git", "tag", "--sort=-version:refname" },
        .cwd_dir = b.build_root.handle,
    }) catch return fallback;
    defer b.allocator.free(result.stdout);
    defer b.allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) return fallback,
        else => return fallback,
    }

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    const first_line = lines.next() orelse return fallback;
    const trimmed = std.mem.trim(u8, std.mem.trimRight(u8, first_line, "\r\n"), " \t");
    if (trimmed.len == 0) return fallback;

    const normalized = if (trimmed[0] == 'v' and trimmed.len > 1)
        trimmed[1..]
    else
        trimmed;
    if (normalized.len == 0) return fallback;

    return b.dupe(normalized);
}
