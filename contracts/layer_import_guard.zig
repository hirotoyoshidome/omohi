const std = @import("std");

const Layer = enum {
    store,
    ops,
    app,
};

const Violation = struct {
    source_file: []const u8,
    import_literal: []const u8,
    resolved_target: []const u8,
    reason: []const u8,
};

pub fn runCheck(allocator: std.mem.Allocator) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var violations = std.ArrayList(Violation){};

    try scanLayer(arena, &violations, "src/store");
    try scanLayer(arena, &violations, "src/ops");
    try scanLayer(arena, &violations, "src/app");

    if (violations.items.len > 0) {
        for (violations.items) |v| {
            std.debug.print(
                "Layer import rule violation: {s} imports \"{s}\" (resolved: {s}) : {s}\n",
                .{ v.source_file, v.import_literal, v.resolved_target, v.reason },
            );
        }
        return error.LayerImportViolation;
    }
}

fn scanLayer(allocator: std.mem.Allocator, violations: *std.ArrayList(Violation), layer_dir: []const u8) !void {
    var dir = try std.fs.cwd().openDir(layer_dir, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;

        const source_file = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ layer_dir, entry.path });
        const source_data = try std.fs.cwd().readFileAlloc(allocator, source_file, 8 * 1024 * 1024);

        var imports = std.ArrayList([]const u8){};
        try collectImportLiterals(allocator, source_data, &imports);

        for (imports.items) |import_literal| {
            const resolved_target = try resolveImportPath(allocator, source_file, import_literal);
            if (resolved_target == null) continue;

            try validateDependency(allocator, violations, source_file, import_literal, resolved_target.?);
        }
    }
}

fn validateDependency(
    allocator: std.mem.Allocator,
    violations: *std.ArrayList(Violation),
    source_file: []const u8,
    import_literal: []const u8,
    resolved_target: []const u8,
) !void {
    const source_layer = layerOf(source_file) orelse return;
    const target_layer = layerOf(resolved_target) orelse return;

    switch (source_layer) {
        .store => {
            if (target_layer != .store) {
                try violations.append(allocator, .{
                    .source_file = source_file,
                    .import_literal = import_literal,
                    .resolved_target = resolved_target,
                    .reason = "store can only import store",
                });
            }
        },
        .ops => {
            if (target_layer == .app) {
                try violations.append(allocator, .{
                    .source_file = source_file,
                    .import_literal = import_literal,
                    .resolved_target = resolved_target,
                    .reason = "ops must not import app",
                });
                return;
            }

            if (target_layer == .store and !std.mem.eql(u8, resolved_target, "src/store/api.zig")) {
                try violations.append(allocator, .{
                    .source_file = source_file,
                    .import_literal = import_literal,
                    .resolved_target = resolved_target,
                    .reason = "ops may import store only via store/api.zig",
                });
            }
        },
        .app => {
            if (target_layer == .store) {
                try violations.append(allocator, .{
                    .source_file = source_file,
                    .import_literal = import_literal,
                    .resolved_target = resolved_target,
                    .reason = "app must not import store directly",
                });
            }
        },
    }
}

fn layerOf(path: []const u8) ?Layer {
    if (std.mem.startsWith(u8, path, "src/store/")) return .store;
    if (std.mem.startsWith(u8, path, "src/ops/")) return .ops;
    if (std.mem.startsWith(u8, path, "src/app/")) return .app;
    return null;
}

fn resolveImportPath(allocator: std.mem.Allocator, source_file: []const u8, import_literal: []const u8) !?[]const u8 {
    if (std.mem.eql(u8, import_literal, "std") or std.mem.eql(u8, import_literal, "builtin")) return null;

    if (std.mem.startsWith(u8, import_literal, "./") or std.mem.startsWith(u8, import_literal, "../")) {
        const source_dir = std.fs.path.dirname(source_file) orelse return null;
        const raw = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ source_dir, import_literal });
        return try normalizeRelativePath(allocator, raw);
    }

    if (std.mem.startsWith(u8, import_literal, "store/") or
        std.mem.startsWith(u8, import_literal, "ops/") or
        std.mem.startsWith(u8, import_literal, "app/"))
    {
        const raw = try std.fmt.allocPrint(allocator, "src/{s}", .{import_literal});
        return try normalizeRelativePath(allocator, raw);
    }

    return null;
}

fn normalizeRelativePath(allocator: std.mem.Allocator, raw_path: []const u8) ![]const u8 {
    var parts = std.ArrayList([]const u8){};

    var it = std.mem.splitScalar(u8, raw_path, '/');
    while (it.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;

        if (std.mem.eql(u8, part, "..")) {
            if (parts.items.len > 0 and !std.mem.eql(u8, parts.items[parts.items.len - 1], "..")) {
                _ = parts.pop();
            } else {
                try parts.append(allocator, part);
            }
            continue;
        }

        try parts.append(allocator, part);
    }

    return std.mem.join(allocator, "/", parts.items);
}

fn collectImportLiterals(
    allocator: std.mem.Allocator,
    source: []const u8,
    imports: *std.ArrayList([]const u8),
) !void {
    var i: usize = 0;
    var block_comment_depth: usize = 0;

    while (i < source.len) {
        if (block_comment_depth > 0) {
            if (i + 1 < source.len and source[i] == '/' and source[i + 1] == '*') {
                block_comment_depth += 1;
                i += 2;
                continue;
            }
            if (i + 1 < source.len and source[i] == '*' and source[i + 1] == '/') {
                block_comment_depth -= 1;
                i += 2;
                continue;
            }
            i += 1;
            continue;
        }

        if (i + 1 < source.len and source[i] == '/' and source[i + 1] == '/') {
            i += 2;
            while (i < source.len and source[i] != '\n') : (i += 1) {}
            continue;
        }

        if (i + 1 < source.len and source[i] == '/' and source[i + 1] == '*') {
            block_comment_depth = 1;
            i += 2;
            continue;
        }

        if (source[i] == '"') {
            i += 1;
            while (i < source.len) {
                if (source[i] == '\\' and i + 1 < source.len) {
                    i += 2;
                    continue;
                }
                if (source[i] == '"') {
                    i += 1;
                    break;
                }
                i += 1;
            }
            continue;
        }

        if (source[i] == '\'') {
            i += 1;
            while (i < source.len) {
                if (source[i] == '\\' and i + 1 < source.len) {
                    i += 2;
                    continue;
                }
                if (source[i] == '\'') {
                    i += 1;
                    break;
                }
                i += 1;
            }
            continue;
        }

        if (startsWithImport(source, i)) {
            var j = i + "@import".len;
            skipWhitespace(source, &j);
            if (j >= source.len or source[j] != '(') {
                i += 1;
                continue;
            }

            j += 1;
            skipWhitespace(source, &j);
            if (j >= source.len or source[j] != '"') {
                i += 1;
                continue;
            }

            j += 1;
            const literal_start = j;
            while (j < source.len) {
                if (source[j] == '\\' and j + 1 < source.len) {
                    j += 2;
                    continue;
                }
                if (source[j] == '"') break;
                j += 1;
            }

            if (j >= source.len) {
                i += 1;
                continue;
            }

            const literal = source[literal_start..j];
            try imports.append(allocator, try allocator.dupe(u8, literal));

            j += 1;
            skipWhitespace(source, &j);
            if (j < source.len and source[j] == ')') {
                i = j + 1;
            } else {
                i += 1;
            }
            continue;
        }

        i += 1;
    }
}

fn startsWithImport(source: []const u8, index: usize) bool {
    const token = "@import";
    if (index + token.len > source.len) return false;
    return std.mem.eql(u8, source[index .. index + token.len], token);
}

fn skipWhitespace(source: []const u8, index: *usize) void {
    while (index.* < source.len and std.ascii.isWhitespace(source[index.*])) {
        index.* += 1;
    }
}
