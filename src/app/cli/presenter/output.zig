const std = @import("std");
const parser_types = @import("../parser/types.zig");
const ansi_color = @import("ansi_color.zig");
const local_time_text = @import("local_time_text.zig");
const add_ops = @import("../../../ops/add_ops.zig");
const rm_ops = @import("../../../ops/rm_ops.zig");
const track_ops = @import("../../../ops/track_ops.zig");
const status_ops = @import("../../../ops/status_ops.zig");
const find_ops = @import("../../../ops/find_ops.zig");
const show_ops = @import("../../../ops/show_ops.zig");
const tag_ops = @import("../../../ops/tag_ops.zig");
const journal_ops = @import("../../../ops/journal_ops.zig");

pub const TagRemoveOutcome = enum {
    no_tags,
    no_matching,
    removed,
};

pub const CommitDryRunEntry = struct {
    path: []const u8,
    missing: bool,
};

// Returns an owned copy of a fixed presenter message.
pub fn message(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return allocator.dupe(u8, text);
}

// Renders the track result as owned CLI output.
pub fn trackResult(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    outcome: *const track_ops.TrackOutcome,
) ![]u8 {
    if (outcome.tracked_paths.items.len == 1 and outcome.skipped_paths == 0 and
        std.mem.eql(u8, outcome.tracked_paths.items[0], absolute_path))
    {
        return std.fmt.allocPrint(allocator, "Tracked: {s}\n", .{absolute_path});
    }

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Tracked {d} file(s) under {s}\n", .{ outcome.tracked_paths.items.len, absolute_path });
    for (outcome.tracked_paths.items) |path| {
        try writer.print("- {s}\n", .{path});
    }
    if (outcome.skipped_paths != 0) {
        try writer.print("Skipped already tracked file(s): {d}\n", .{outcome.skipped_paths});
    }

    return out.toOwnedSlice();
}

// Renders aggregated track results for multiple explicit path inputs.
pub fn trackMultiResult(allocator: std.mem.Allocator, outcome: *const track_ops.TrackOutcome) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Tracked {d} file(s).\n", .{outcome.tracked_paths.items.len});
    for (outcome.tracked_paths.items) |path| {
        try writer.print("- {s}\n", .{path});
    }
    if (outcome.skipped_paths != 0) {
        try writer.print("Skipped already tracked file(s): {d}\n", .{outcome.skipped_paths});
    }

    return out.toOwnedSlice();
}

// Renders the untrack result as owned CLI output.
pub fn untrackResult(allocator: std.mem.Allocator, absolute_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "Untracked: {s}\n", .{absolute_path});
}

// Renders the bulk missing-untrack result as owned CLI output.
pub fn untrackMissingResult(
    allocator: std.mem.Allocator,
    outcome: *const track_ops.UntrackMissingOutcome,
) ![]u8 {
    if (outcome.untracked_paths.items.len == 0) {
        return allocator.dupe(u8, "No missing tracked files to untrack.\n");
    }

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Untracked {d} missing tracked file(s).\n", .{outcome.untracked_paths.items.len});
    for (outcome.untracked_paths.items) |path| {
        try writer.print("- {s}\n", .{path});
    }

    return out.toOwnedSlice();
}

// Renders add results as owned CLI output, including skipped-path summaries when needed.
pub fn addResult(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    outcome: *const add_ops.AddOutcome,
) ![]u8 {
    if (outcome.staged_paths.items.len == 1 and
        outcome.skipped_untracked == 0 and
        outcome.skipped_missing == 0 and
        outcome.skipped_non_regular == 0 and
        outcome.skipped_already_staged == 0 and
        outcome.skipped_no_change == 0 and
        std.mem.eql(u8, outcome.staged_paths.items[0], absolute_path))
    {
        return std.fmt.allocPrint(allocator, "Staged: {s}\n", .{absolute_path});
    }

    if (outcome.staged_paths.items.len == 0 and
        outcome.skipped_untracked == 0 and
        outcome.skipped_missing == 0 and
        outcome.skipped_non_regular == 0 and
        outcome.skipped_already_staged == 0 and
        outcome.skipped_no_change == 1)
    {
        return std.fmt.allocPrint(allocator, "No changes to stage: {s}\n", .{absolute_path});
    }

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Staged {d} file(s) under {s}\n", .{ outcome.staged_paths.items.len, absolute_path });
    for (outcome.staged_paths.items) |path| {
        try writer.print("- {s}\n", .{path});
    }
    if (outcome.skipped_untracked != 0) {
        try writer.print("Skipped untracked file(s): {d}\n", .{outcome.skipped_untracked});
    }
    if (outcome.skipped_missing != 0) {
        try writer.print("Skipped missing tracked file(s): {d}\n", .{outcome.skipped_missing});
    }
    if (outcome.skipped_already_staged != 0) {
        try writer.print("Skipped already staged file(s): {d}\n", .{outcome.skipped_already_staged});
    }
    if (outcome.skipped_no_change != 0) {
        try writer.print("Skipped unchanged file(s): {d}\n", .{outcome.skipped_no_change});
    }
    if (outcome.skipped_non_regular != 0) {
        try writer.print("Skipped non-regular entry(s): {d}\n", .{outcome.skipped_non_regular});
    }

    return out.toOwnedSlice();
}

// Renders aggregated add results for multiple explicit path inputs.
pub fn addMultiResult(allocator: std.mem.Allocator, outcome: *const add_ops.AddOutcome) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Staged {d} file(s).\n", .{outcome.staged_paths.items.len});
    for (outcome.staged_paths.items) |path| {
        try writer.print("- {s}\n", .{path});
    }
    if (outcome.skipped_untracked != 0) {
        try writer.print("Skipped untracked file(s): {d}\n", .{outcome.skipped_untracked});
    }
    if (outcome.skipped_missing != 0) {
        try writer.print("Skipped missing tracked file(s): {d}\n", .{outcome.skipped_missing});
    }
    if (outcome.skipped_already_staged != 0) {
        try writer.print("Skipped already staged file(s): {d}\n", .{outcome.skipped_already_staged});
    }
    if (outcome.skipped_no_change != 0) {
        try writer.print("Skipped unchanged file(s): {d}\n", .{outcome.skipped_no_change});
    }
    if (outcome.skipped_non_regular != 0) {
        try writer.print("Skipped non-regular entry(s): {d}\n", .{outcome.skipped_non_regular});
    }

    return out.toOwnedSlice();
}

// Renders rm results as owned CLI output, including skipped-path summaries when needed.
pub fn rmResult(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    outcome: *const rm_ops.RmOutcome,
) ![]u8 {
    if (outcome.unstaged_paths.items.len == 1 and
        outcome.skipped_untracked == 0 and
        outcome.skipped_not_staged == 0 and
        outcome.skipped_non_regular == 0 and
        std.mem.eql(u8, outcome.unstaged_paths.items[0], absolute_path))
    {
        return std.fmt.allocPrint(allocator, "Unstaged: {s}\n", .{absolute_path});
    }

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Unstaged {d} file(s) under {s}\n", .{ outcome.unstaged_paths.items.len, absolute_path });
    for (outcome.unstaged_paths.items) |path| {
        try writer.print("- {s}\n", .{path});
    }
    if (outcome.skipped_untracked != 0) {
        try writer.print("Skipped untracked file(s): {d}\n", .{outcome.skipped_untracked});
    }
    if (outcome.skipped_not_staged != 0) {
        try writer.print("Skipped non-staged file(s): {d}\n", .{outcome.skipped_not_staged});
    }
    if (outcome.skipped_non_regular != 0) {
        try writer.print("Skipped non-regular entry(s): {d}\n", .{outcome.skipped_non_regular});
    }

    return out.toOwnedSlice();
}

// Renders aggregated rm results for multiple explicit path inputs.
pub fn rmMultiResult(allocator: std.mem.Allocator, outcome: *const rm_ops.RmOutcome) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Unstaged {d} file(s).\n", .{outcome.unstaged_paths.items.len});
    for (outcome.unstaged_paths.items) |path| {
        try writer.print("- {s}\n", .{path});
    }
    if (outcome.skipped_untracked != 0) {
        try writer.print("Skipped untracked file(s): {d}\n", .{outcome.skipped_untracked});
    }
    if (outcome.skipped_not_staged != 0) {
        try writer.print("Skipped non-staged file(s): {d}\n", .{outcome.skipped_not_staged});
    }
    if (outcome.skipped_non_regular != 0) {
        try writer.print("Skipped non-regular entry(s): {d}\n", .{outcome.skipped_non_regular});
    }

    return out.toOwnedSlice();
}

// Renders the created commit id as owned CLI output.
pub fn commitResult(allocator: std.mem.Allocator, commit_id: [64]u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "Committed {s}.\n", .{&commit_id});
}

// Renders journal entries as owned CLI output.
pub fn journalResult(
    allocator: std.mem.Allocator,
    entries: *const journal_ops.JournalList,
) ![]u8 {
    if (entries.items.len == 0) return message(allocator, "no journal entries\n");

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    for (entries.items) |entry| {
        try writer.print("{s} {s} {s}\n", .{
            entry.local_ts,
            entry.command_type,
            entry.payload_json,
        });
    }

    return out.toOwnedSlice();
}

// Renders tracked entries as owned CLI output.
pub fn tracklistResult(
    allocator: std.mem.Allocator,
    list: *const track_ops.TrackedList,
    args: parser_types.TracklistArgs,
) ![]u8 {
    if (args.output == .json) return renderTracklistJson(allocator, list, args.fields);
    if (args.fields.len != 0) return renderTracklistFieldText(allocator, list, args.fields);

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    if (list.items.len == 0) {
        try writer.writeAll("no tracked files\n");
        return out.toOwnedSlice();
    }

    for (list.items) |entry| {
        try writer.print("{s} {s}\n", .{ entry.id.asSlice(), entry.path.asSlice() });
    }
    return out.toOwnedSlice();
}

// Renders staged and changed status entries as owned CLI output.
pub fn statusResult(
    allocator: std.mem.Allocator,
    list: *const status_ops.StatusList,
    enable_color: bool,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();
    var rendered_count: usize = 0;
    for (list.items) |entry| {
        if (entry.status != .staged) continue;
        rendered_count += 1;
        try writeStatusLine(writer, "staged:", .green, entry.path, enable_color);
    }

    for (list.items) |entry| {
        if (entry.status != .tracked and entry.status != .changed) continue;
        rendered_count += 1;
        try writeStatusLine(writer, "changed:", .red, entry.path, enable_color);
    }

    var missing_count: usize = 0;
    for (list.items) |entry| {
        if (entry.status != .missing) continue;
        rendered_count += 1;
        missing_count += 1;
        try writeStatusLine(writer, "missing:", .gray, entry.path, enable_color);
    }

    if (rendered_count == 0) {
        try writer.writeAll("no staged, changed, or missing tracked files\n");
    } else if (missing_count != 0) {
        try writer.writeAll(
            "Missing tracked files remain. Use `omohi untrack --missing` to clear them explicitly.\n",
        );
    }

    return out.toOwnedSlice();
}

// Writes one line of human-readable status output.
fn writeStatusLine(
    writer: anytype,
    label: []const u8,
    color: ansi_color.Color,
    path: []const u8,
    enable_color: bool,
) !void {
    try ansi_color.writeColored(writer, label, color, enable_color);
    try writer.print(" {s}\n", .{path});
}

// Renders find results as owned CLI output and includes active filter context.
pub fn findResult(
    allocator: std.mem.Allocator,
    list: *const find_ops.CommitSummaryList,
    args: parser_types.FindArgs,
) ![]u8 {
    if (args.output == .json) return renderFindJson(allocator, list, args.fields);
    if (args.fields.len != 0) return renderFindFieldText(allocator, list, args.fields);

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    if (list.items.len == 0) {
        try writer.writeAll("no commits\n");
        return out.toOwnedSlice();
    }

    try writeFindHeading(writer, list.items.len, args);

    for (list.items) |entry| {
        try writer.print("- {s}\n", .{entry.commit_id.asSlice()});
        try writer.print("  {s}\n\n", .{entry.local_created_at});
        try writer.print("  {s}\n\n", .{entry.message});
    }
    return out.toOwnedSlice();
}

// Writes the summary heading for a `find` text result with active filters.
fn writeFindHeading(writer: anytype, count: usize, args: parser_types.FindArgs) !void {
    if (args.tag) |tag_name| {
        if (args.since) |since_value| {
            if (args.until) |until_value| {
                try writer.print("Found {d} commit(s) for tag {s} from {s} until {s}.\n", .{ count, tag_name, since_value, until_value });
                return;
            }
            try writer.print("Found {d} commit(s) for tag {s} since {s}.\n", .{ count, tag_name, since_value });
            return;
        }
        if (args.until) |until_value| {
            try writer.print("Found {d} commit(s) for tag {s} until {s}.\n", .{ count, tag_name, until_value });
            return;
        }
        try writer.print("Found {d} commit(s) for tag {s}.\n", .{ count, tag_name });
        return;
    }

    if (args.since) |since_value| {
        if (args.until) |until_value| {
            try writer.print("Found {d} commit(s) from {s} until {s}.\n", .{ count, since_value, until_value });
            return;
        }
        try writer.print("Found {d} commit(s) since {s}.\n", .{ count, since_value });
        return;
    }

    if (args.until) |until_value| {
        try writer.print("Found {d} commit(s) until {s}.\n", .{ count, until_value });
        return;
    }

    try writer.print("Found {d} commit(s).\n", .{count});
}

// Renders commit details and related tags as owned CLI output.
pub fn showResult(
    allocator: std.mem.Allocator,
    details: *const show_ops.CommitDetails,
    args: parser_types.ShowArgs,
) ![]u8 {
    if (args.output == .json) return renderShowJson(allocator, details, args.fields);
    if (args.fields.len != 0) return renderShowFieldText(allocator, details, args.fields);

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();
    const local_created_at = try local_time_text.dupeLocalTimestampOrOriginal(allocator, details.created_at);
    defer allocator.free(local_created_at);

    try writer.print("Found commit {s}\n", .{details.commit_id.asSlice()});
    try writer.print("{s}\n\n", .{local_created_at});
    try writer.print("{s}\n\n", .{details.message});

    try writer.writeAll("commit changes:\n");
    for (details.entries.items) |entry| {
        try writer.print("- {s}\n", .{entry.path.asSlice()});
    }

    try writer.writeAll("tags:\n");
    if (details.tags.items.len == 0) {
        try writer.writeAll("- (none)\n");
    } else {
        for (details.tags.items) |tag_name| {
            try writer.print("- {s}\n", .{tag_name});
        }
    }

    return out.toOwnedSlice();
}

// Renders `tracklist` as selected-value text lines.
fn renderTracklistFieldText(
    allocator: std.mem.Allocator,
    list: *const track_ops.TrackedList,
    fields: []const parser_types.TracklistField,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    for (list.items) |entry| {
        var first = true;
        for (fields) |field| {
            const value = switch (field) {
                .id => entry.id.asSlice(),
                .path => entry.path.asSlice(),
            };
            try writeSelectedValue(writer, &first, value);
        }
        try writer.writeByte('\n');
    }

    return out.toOwnedSlice();
}

// Renders `tracklist` as a JSON array of filtered objects.
fn renderTracklistJson(
    allocator: std.mem.Allocator,
    list: *const track_ops.TrackedList,
    fields: []const parser_types.TracklistField,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.writeByte('[');
    for (list.items, 0..) |entry, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        var first = true;

        if (shouldIncludeTracklistField(fields, .id)) {
            try writeJsonFieldSeparator(writer, &first);
            try writer.print("\"id\":{f}", .{std.json.fmt(entry.id.asSlice(), .{})});
        }
        if (shouldIncludeTracklistField(fields, .path)) {
            try writeJsonFieldSeparator(writer, &first);
            try writer.print("\"path\":{f}", .{std.json.fmt(entry.path.asSlice(), .{})});
        }

        try writer.writeByte('}');
    }
    try writer.writeByte(']');

    return out.toOwnedSlice();
}

// Renders `find` as selected-value text lines.
fn renderFindFieldText(
    allocator: std.mem.Allocator,
    list: *const find_ops.CommitSummaryList,
    fields: []const parser_types.FindField,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    for (list.items) |entry| {
        var first = true;
        for (fields) |field| {
            const value = switch (field) {
                .commit_id => entry.commit_id.asSlice(),
                .message => entry.message,
                .created_at => entry.local_created_at,
            };
            try writeSelectedValue(writer, &first, value);
        }
        try writer.writeByte('\n');
    }

    return out.toOwnedSlice();
}

// Renders `find` as a JSON array of filtered objects.
fn renderFindJson(
    allocator: std.mem.Allocator,
    list: *const find_ops.CommitSummaryList,
    fields: []const parser_types.FindField,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.writeByte('[');
    for (list.items, 0..) |entry, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        var first = true;

        if (shouldIncludeFindField(fields, .commit_id)) {
            try writeJsonFieldSeparator(writer, &first);
            try writer.print("\"commit_id\":{f}", .{std.json.fmt(entry.commit_id.asSlice(), .{})});
        }
        if (shouldIncludeFindField(fields, .message)) {
            try writeJsonFieldSeparator(writer, &first);
            try writer.print("\"message\":{f}", .{std.json.fmt(entry.message, .{})});
        }
        if (shouldIncludeFindField(fields, .created_at)) {
            try writeJsonFieldSeparator(writer, &first);
            try writer.print("\"created_at\":{f}", .{std.json.fmt(entry.local_created_at, .{})});
        }

        try writer.writeByte('}');
    }
    try writer.writeByte(']');

    return out.toOwnedSlice();
}

// Renders `show` as one selected-value text line.
fn renderShowFieldText(
    allocator: std.mem.Allocator,
    details: *const show_ops.CommitDetails,
    fields: []const parser_types.ShowField,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();
    const local_created_at = try local_time_text.dupeLocalTimestampOrOriginal(allocator, details.created_at);
    defer allocator.free(local_created_at);

    var first = true;
    for (fields) |field| {
        switch (field) {
            .commit_id => try writeSelectedValue(writer, &first, details.commit_id.asSlice()),
            .message => try writeSelectedValue(writer, &first, details.message),
            .created_at => try writeSelectedValue(writer, &first, local_created_at),
            .paths => {
                const joined = try joinShowPaths(allocator, details);
                defer allocator.free(joined);
                try writeSelectedValue(writer, &first, joined);
            },
            .tags => {
                const joined = try joinTagsCsv(allocator, details.tags.items);
                defer allocator.free(joined);
                try writeSelectedValue(writer, &first, joined);
            },
        }
    }
    try writer.writeByte('\n');

    return out.toOwnedSlice();
}

// Renders `show` as a filtered JSON object.
fn renderShowJson(
    allocator: std.mem.Allocator,
    details: *const show_ops.CommitDetails,
    fields: []const parser_types.ShowField,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();
    const local_created_at = try local_time_text.dupeLocalTimestampOrOriginal(allocator, details.created_at);
    defer allocator.free(local_created_at);

    try writer.writeByte('{');
    var first = true;

    if (shouldIncludeShowField(fields, .commit_id)) {
        try writeJsonFieldSeparator(writer, &first);
        try writer.print("\"commit_id\":{f}", .{std.json.fmt(details.commit_id.asSlice(), .{})});
    }
    if (shouldIncludeShowField(fields, .message)) {
        try writeJsonFieldSeparator(writer, &first);
        try writer.print("\"message\":{f}", .{std.json.fmt(details.message, .{})});
    }
    if (shouldIncludeShowField(fields, .created_at)) {
        try writeJsonFieldSeparator(writer, &first);
        try writer.print("\"created_at\":{f}", .{std.json.fmt(local_created_at, .{})});
    }
    if (shouldIncludeShowField(fields, .paths)) {
        try writeJsonFieldSeparator(writer, &first);
        try writer.writeAll("\"paths\":[");
        for (details.entries.items, 0..) |entry, idx| {
            if (idx != 0) try writer.writeByte(',');
            try writer.print("{f}", .{std.json.fmt(entry.path.asSlice(), .{})});
        }
        try writer.writeByte(']');
    }
    if (shouldIncludeShowField(fields, .tags)) {
        try writeJsonFieldSeparator(writer, &first);
        try writer.writeAll("\"tags\":[");
        for (details.tags.items, 0..) |tag_name, idx| {
            if (idx != 0) try writer.writeByte(',');
            try writer.print("{f}", .{std.json.fmt(tag_name, .{})});
        }
        try writer.writeByte(']');
    }

    try writer.writeByte('}');
    return out.toOwnedSlice();
}

// Renders tags for a commit as owned CLI output.
pub fn tagListResult(
    allocator: std.mem.Allocator,
    commit_id: []const u8,
    tags: *const tag_ops.TagList,
    fields: []const parser_types.TagField,
) ![]u8 {
    if (fields.len != 0) return writeTagFieldLines(allocator, tags.items, fields);

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Found {d} tag(s) for commit {s}.\n", .{ tags.items.len, commit_id });
    try writeTagLines(writer, tags.items);

    return out.toOwnedSlice();
}

// Renders the global tag-name list as owned CLI output.
pub fn tagNameListResult(
    allocator: std.mem.Allocator,
    tags: *const tag_ops.TagNameList,
    fields: []const parser_types.TagField,
) ![]u8 {
    if (fields.len != 0) return writeTagFieldLines(allocator, tags.items, fields);

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Found {d} tag(s).\n", .{tags.items.len});
    try writeTagLines(writer, tags.items);

    return out.toOwnedSlice();
}

// Renders the outcome of `tag add` as owned CLI output.
pub fn tagAddResult(
    allocator: std.mem.Allocator,
    commit_id: []const u8,
    added_count: usize,
    tags: *const tag_ops.TagList,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    if (added_count == 0) {
        try writer.print(
            "No new tags were added; commit {s} already has the specified tags.\n",
            .{commit_id},
        );
    } else {
        try writer.print("Added {d} tag(s) to commit {s}.\n", .{ added_count, commit_id });
    }
    try writeTagCsvLine(writer, tags.items);

    return out.toOwnedSlice();
}

// Renders the outcome of `tag rm` as owned CLI output.
pub fn tagRmResult(
    allocator: std.mem.Allocator,
    commit_id: []const u8,
    removed_count: usize,
    outcome: TagRemoveOutcome,
    tags: *const tag_ops.TagList,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    switch (outcome) {
        .no_tags => try writer.print("Commit {s} has no tags to remove.\n", .{commit_id}),
        .no_matching => try writer.print("No matching tags found to remove from commit {s}.\n", .{commit_id}),
        .removed => try writer.print("Removed {d} tag(s) from commit {s}.\n", .{ removed_count, commit_id }),
    }
    try writeTagCsvLine(writer, tags.items);

    return out.toOwnedSlice();
}

// Renders dry-run commit output as owned CLI text without mutating store state.
pub fn commitDryRunResult(
    allocator: std.mem.Allocator,
    staged_count: usize,
    staged_entries: []const CommitDryRunEntry,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.writeAll("Dry run: commit prepared but not written.\n");
    try writer.print("dry-run staged count: {d}\n", .{staged_count});
    for (staged_entries) |entry| {
        if (entry.missing) {
            try writer.print("- {s} (missing)\n", .{entry.path});
        } else {
            try writer.print("- {s}\n", .{entry.path});
        }
    }
    return out.toOwnedSlice();
}

// Writes tags as a single CSV line and writes `(none)` when the list is empty.
fn writeTagCsvLine(writer: anytype, tags: []const []u8) !void {
    if (tags.len == 0) {
        try writer.writeAll("(none)\n");
        return;
    }

    for (tags, 0..) |tag_name, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeAll(tag_name);
    }
    try writer.writeByte('\n');
}

// Writes tags as one item per line and falls back to `(none)` for empty lists.
fn writeTagLines(writer: anytype, tags: []const []u8) !void {
    if (tags.len == 0) {
        try writer.writeAll("(none)\n");
        return;
    }

    for (tags) |tag_name| {
        try writer.writeAll(tag_name);
        try writer.writeByte('\n');
    }
}

// Writes one line per tag for selected tag fields and emits nothing for empty lists.
fn writeTagFieldLines(
    allocator: std.mem.Allocator,
    tags: []const []u8,
    fields: []const parser_types.TagField,
) ![]u8 {
    if (!containsTagField(fields, .tag)) return allocator.alloc(u8, 0);

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    for (tags) |tag_name| {
        try writer.writeAll(tag_name);
        try writer.writeByte('\n');
    }

    return out.toOwnedSlice();
}

// Writes one selected text value with a leading space separator after the first column.
fn writeSelectedValue(writer: anytype, first: *bool, value: []const u8) !void {
    if (!first.*) try writer.writeByte(' ');
    first.* = false;
    try writer.writeAll(value);
}

// Writes a comma before subsequent JSON object fields.
fn writeJsonFieldSeparator(writer: anytype, first: *bool) !void {
    if (!first.*) try writer.writeByte(',');
    first.* = false;
}

// Reports whether a `tracklist` field should be included in filtered output.
fn shouldIncludeTracklistField(fields: []const parser_types.TracklistField, needle: parser_types.TracklistField) bool {
    return fields.len == 0 or containsTracklistField(fields, needle);
}

// Reports whether a `find` field should be included in filtered output.
fn shouldIncludeFindField(fields: []const parser_types.FindField, needle: parser_types.FindField) bool {
    return fields.len == 0 or containsFindField(fields, needle);
}

// Reports whether a `show` field should be included in filtered output.
fn shouldIncludeShowField(fields: []const parser_types.ShowField, needle: parser_types.ShowField) bool {
    return fields.len == 0 or containsShowField(fields, needle);
}

// Reports whether the given `tracklist` field list contains the requested field.
fn containsTracklistField(fields: []const parser_types.TracklistField, needle: parser_types.TracklistField) bool {
    for (fields) |field| {
        if (field == needle) return true;
    }
    return false;
}

// Reports whether the given `find` field list contains the requested field.
fn containsFindField(fields: []const parser_types.FindField, needle: parser_types.FindField) bool {
    for (fields) |field| {
        if (field == needle) return true;
    }
    return false;
}

// Reports whether the given `show` field list contains the requested field.
fn containsShowField(fields: []const parser_types.ShowField, needle: parser_types.ShowField) bool {
    for (fields) |field| {
        if (field == needle) return true;
    }
    return false;
}

// Reports whether the given `tag` field list contains the requested field.
fn containsTagField(fields: []const parser_types.TagField, needle: parser_types.TagField) bool {
    for (fields) |field| {
        if (field == needle) return true;
    }
    return false;
}

// Joins show-path values into a single CSV-style string for text field output.
fn joinShowPaths(allocator: std.mem.Allocator, details: *const show_ops.CommitDetails) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    for (details.entries.items, 0..) |entry, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeAll(entry.path.asSlice());
    }

    return out.toOwnedSlice();
}

// Joins tags into a single CSV-style string for text field output.
fn joinTagsCsv(allocator: std.mem.Allocator, tags: []const []u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    for (tags, 0..) |tag_name, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeAll(tag_name);
    }

    return out.toOwnedSlice();
}

// Fills a 32-byte test id with the requested byte.
fn filled32(ch: u8) [32]u8 {
    var value: [32]u8 = undefined;
    @memset(&value, ch);
    return value;
}

// Fills a 64-byte test id with the requested byte.
fn filled64(ch: u8) [64]u8 {
    var value: [64]u8 = undefined;
    @memset(&value, ch);
    return value;
}

// Builds owned commit details for presenter tests and leaves cleanup to `show_ops.freeCommitDetails`.
fn initTestCommitDetails(
    allocator: std.mem.Allocator,
    commit_id: [64]u8,
    snapshot_id: [64]u8,
    commit_message: []const u8,
    created_at: []const u8,
) !show_ops.CommitDetails {
    const EntryList = @TypeOf(@as(show_ops.CommitDetails, undefined).entries);
    const TagList = @TypeOf(@as(show_ops.CommitDetails, undefined).tags);

    return .{
        .commit_id = .{ .value = commit_id },
        .snapshot_id = .{ .value = snapshot_id },
        .message = try allocator.dupe(u8, commit_message),
        .created_at = try allocator.dupe(u8, created_at),
        .entries = EntryList.init(allocator),
        .tags = TagList.init(allocator),
    };
}

test "trackResult follows migration contract" {
    var outcome = track_ops.TrackOutcome.init(std.testing.allocator);
    defer track_ops.freeTrackOutcome(std.testing.allocator, &outcome);
    try outcome.tracked_paths.append(try std.testing.allocator.dupe(u8, "/tmp/a.txt"));

    const output = try trackResult(std.testing.allocator, "/tmp/a.txt", &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("Tracked: /tmp/a.txt\n", output);
}

test "trackResult renders directory expansion summary" {
    var outcome = track_ops.TrackOutcome.init(std.testing.allocator);
    defer track_ops.freeTrackOutcome(std.testing.allocator, &outcome);
    try outcome.tracked_paths.append(try std.testing.allocator.dupe(u8, "/tmp/root/a.txt"));
    try outcome.tracked_paths.append(try std.testing.allocator.dupe(u8, "/tmp/root/sub/b.txt"));
    outcome.skipped_paths = 1;

    const output = try trackResult(std.testing.allocator, "/tmp/root", &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Tracked 2 file(s) under /tmp/root\n" ++
            "- /tmp/root/a.txt\n" ++
            "- /tmp/root/sub/b.txt\n" ++
            "Skipped already tracked file(s): 1\n",
        output,
    );
}

test "trackMultiResult renders aggregated summary without under-clause" {
    var outcome = track_ops.TrackOutcome.init(std.testing.allocator);
    defer track_ops.freeTrackOutcome(std.testing.allocator, &outcome);
    try outcome.tracked_paths.append(try std.testing.allocator.dupe(u8, "/tmp/a.txt"));
    try outcome.tracked_paths.append(try std.testing.allocator.dupe(u8, "/tmp/b.txt"));
    outcome.skipped_paths = 1;

    const output = try trackMultiResult(std.testing.allocator, &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Tracked 2 file(s).\n" ++
            "- /tmp/a.txt\n" ++
            "- /tmp/b.txt\n" ++
            "Skipped already tracked file(s): 1\n",
        output,
    );
}

test "untrackResult follows migration contract" {
    const output = try untrackResult(std.testing.allocator, "/tmp/a.txt");
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("Untracked: /tmp/a.txt\n", output);
}

test "addResult follows migration contract" {
    var outcome = add_ops.AddOutcome.init(std.testing.allocator);
    defer add_ops.freeAddOutcome(std.testing.allocator, &outcome);
    try outcome.staged_paths.append(try std.testing.allocator.dupe(u8, "/tmp/a.txt"));

    const output = try addResult(std.testing.allocator, "/tmp/a.txt", &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("Staged: /tmp/a.txt\n", output);
}

test "rmResult follows migration contract" {
    var outcome = rm_ops.RmOutcome.init(std.testing.allocator);
    defer rm_ops.freeRmOutcome(std.testing.allocator, &outcome);
    try outcome.unstaged_paths.append(try std.testing.allocator.dupe(u8, "/tmp/a.txt"));

    const output = try rmResult(std.testing.allocator, "/tmp/a.txt", &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("Unstaged: /tmp/a.txt\n", output);
}

test "addResult renders directory summary" {
    var outcome = add_ops.AddOutcome.init(std.testing.allocator);
    defer add_ops.freeAddOutcome(std.testing.allocator, &outcome);
    try outcome.staged_paths.append(try std.testing.allocator.dupe(u8, "/tmp/root/a.txt"));
    outcome.skipped_untracked = 2;
    outcome.skipped_missing = 1;
    outcome.skipped_already_staged = 1;
    outcome.skipped_no_change = 3;

    const output = try addResult(std.testing.allocator, "/tmp/root", &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Staged 1 file(s) under /tmp/root\n" ++
            "- /tmp/root/a.txt\n" ++
            "Skipped untracked file(s): 2\n" ++
            "Skipped missing tracked file(s): 1\n" ++
            "Skipped already staged file(s): 1\n" ++
            "Skipped unchanged file(s): 3\n",
        output,
    );
}

test "addResult renders unchanged single file message" {
    var outcome = add_ops.AddOutcome.init(std.testing.allocator);
    defer add_ops.freeAddOutcome(std.testing.allocator, &outcome);
    outcome.skipped_no_change = 1;

    const output = try addResult(std.testing.allocator, "/tmp/a.txt", &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("No changes to stage: /tmp/a.txt\n", output);
}

test "addMultiResult renders aggregated summary without under-clause" {
    var outcome = add_ops.AddOutcome.init(std.testing.allocator);
    defer add_ops.freeAddOutcome(std.testing.allocator, &outcome);
    try outcome.staged_paths.append(try std.testing.allocator.dupe(u8, "/tmp/a.txt"));
    try outcome.staged_paths.append(try std.testing.allocator.dupe(u8, "/tmp/b.txt"));
    outcome.skipped_untracked = 2;
    outcome.skipped_missing = 1;
    outcome.skipped_already_staged = 1;
    outcome.skipped_no_change = 3;

    const output = try addMultiResult(std.testing.allocator, &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Staged 2 file(s).\n" ++
            "- /tmp/a.txt\n" ++
            "- /tmp/b.txt\n" ++
            "Skipped untracked file(s): 2\n" ++
            "Skipped missing tracked file(s): 1\n" ++
            "Skipped already staged file(s): 1\n" ++
            "Skipped unchanged file(s): 3\n",
        output,
    );
}

test "rmResult renders directory summary" {
    var outcome = rm_ops.RmOutcome.init(std.testing.allocator);
    defer rm_ops.freeRmOutcome(std.testing.allocator, &outcome);
    try outcome.unstaged_paths.append(try std.testing.allocator.dupe(u8, "/tmp/root/a.txt"));
    outcome.skipped_not_staged = 1;
    outcome.skipped_untracked = 2;

    const output = try rmResult(std.testing.allocator, "/tmp/root", &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Unstaged 1 file(s) under /tmp/root\n" ++
            "- /tmp/root/a.txt\n" ++
            "Skipped untracked file(s): 2\n" ++
            "Skipped non-staged file(s): 1\n",
        output,
    );
}

test "rmMultiResult renders aggregated summary without under-clause" {
    var outcome = rm_ops.RmOutcome.init(std.testing.allocator);
    defer rm_ops.freeRmOutcome(std.testing.allocator, &outcome);
    try outcome.unstaged_paths.append(try std.testing.allocator.dupe(u8, "/tmp/a.txt"));
    try outcome.unstaged_paths.append(try std.testing.allocator.dupe(u8, "/tmp/b.txt"));
    outcome.skipped_not_staged = 1;
    outcome.skipped_untracked = 2;

    const output = try rmMultiResult(std.testing.allocator, &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Unstaged 2 file(s).\n" ++
            "- /tmp/a.txt\n" ++
            "- /tmp/b.txt\n" ++
            "Skipped untracked file(s): 2\n" ++
            "Skipped non-staged file(s): 1\n",
        output,
    );
}

test "commitResult follows migration contract" {
    var commit_id: [64]u8 = undefined;
    @memset(&commit_id, 'a');

    const output = try commitResult(std.testing.allocator, commit_id);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Committed aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.\n",
        output,
    );
}

test "tracklistResult renders id and path" {
    var list = track_ops.TrackedList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(@constCast(entry.path.asSlice()));
        list.deinit();
    }

    const path = try std.testing.allocator.dupe(u8, "/tmp/tracked.txt");
    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = .{ .value = path },
    });

    const output = try tracklistResult(std.testing.allocator, &list, .{
        .output = .text,
        .fields = &.{},
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa /tmp/tracked.txt\n",
        output,
    );
}

test "tracklistResult renders selected fields as json" {
    var list = track_ops.TrackedList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(@constCast(entry.path.asSlice()));
        list.deinit();
    }

    const path = try std.testing.allocator.dupe(u8, "/tmp/tracked.txt");
    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = .{ .value = path },
    });

    const output = try tracklistResult(std.testing.allocator, &list, .{
        .output = .json,
        .fields = &.{.path},
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("[{\"path\":\"/tmp/tracked.txt\"}]", output);
}

test "tracklistResult renders no tracked files message" {
    var list = track_ops.TrackedList.init(std.testing.allocator);
    defer list.deinit();

    const output = try tracklistResult(std.testing.allocator, &list, .{
        .output = .text,
        .fields = &.{},
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("no tracked files\n", output);
}

test "tracklistResult renders selected id field as text" {
    var list = track_ops.TrackedList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(@constCast(entry.path.asSlice()));
        list.deinit();
    }

    const path = try std.testing.allocator.dupe(u8, "/tmp/tracked.txt");
    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = .{ .value = path },
    });

    const output = try tracklistResult(std.testing.allocator, &list, .{
        .output = .text,
        .fields = &.{.id},
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", output);
}

test "tracklistResult renders selected id and path fields as text" {
    var list = track_ops.TrackedList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(@constCast(entry.path.asSlice()));
        list.deinit();
    }

    const path = try std.testing.allocator.dupe(u8, "/tmp/tracked.txt");
    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = .{ .value = path },
    });

    const output = try tracklistResult(std.testing.allocator, &list, .{
        .output = .text,
        .fields = &.{ .id, .path },
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa /tmp/tracked.txt\n",
        output,
    );
}

test "findResult renders heading and commit blocks" {
    var list = find_ops.CommitSummaryList.init(std.testing.allocator);
    defer {
        find_ops.freeCommitSummaryList(std.testing.allocator, &list);
    }

    try list.append(.{
        .commit_id = .{ .value = filled64('a') },
        .message = try std.testing.allocator.dupe(u8, "first"),
        .created_at = try std.testing.allocator.dupe(u8, "2026-03-10T00:00:00.000Z"),
        .local_created_at = try std.testing.allocator.dupe(u8, "2026-03-10T09:00:00.000+09:00"),
    });

    const output = try findResult(std.testing.allocator, &list, .{
        .tag = "release",
        .empty_filter = .all,
        .since = null,
        .until = null,
        .since_millis = null,
        .until_millis = null,
        .limit = null,
        .output = .text,
        .fields = &.{},
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Found 1 commit(s) for tag release.\n" ++
            "- aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n" ++
            "  2026-03-10T09:00:00.000+09:00\n\n" ++
            "  first\n\n",
        output,
    );
}

test "journalResult renders local timestamp, command type, and payload" {
    var entries = journal_ops.JournalList.init(std.testing.allocator);
    defer journal_ops.freeJournalList(std.testing.allocator, &entries);

    try entries.append(.{
        .local_ts = try std.testing.allocator.dupe(u8, "2026-03-10T09:00:00.000+09:00"),
        .command_type = try std.testing.allocator.dupe(u8, "track"),
        .payload_json = try std.testing.allocator.dupe(u8, "{\"path\":\"/tmp/one\"}"),
    });
    try entries.append(.{
        .local_ts = try std.testing.allocator.dupe(u8, "2026-03-10T09:00:01.000+09:00"),
        .command_type = try std.testing.allocator.dupe(u8, "add"),
        .payload_json = try std.testing.allocator.dupe(u8, "{\"message\":\"hello world\"}"),
    });

    const output = try journalResult(std.testing.allocator, &entries);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "2026-03-10T09:00:00.000+09:00 track {\"path\":\"/tmp/one\"}\n" ++
            "2026-03-10T09:00:01.000+09:00 add {\"message\":\"hello world\"}\n",
        output,
    );
    try std.testing.expect(std.mem.indexOf(u8, output, "2026-03-10T00:00:00.000Z") == null);
}

test "journalResult renders empty message when no entries exist" {
    var entries = journal_ops.JournalList.init(std.testing.allocator);
    defer journal_ops.freeJournalList(std.testing.allocator, &entries);

    const output = try journalResult(std.testing.allocator, &entries);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("no journal entries\n", output);
}

test "findResult renders selected fields as text rows" {
    var list = find_ops.CommitSummaryList.init(std.testing.allocator);
    defer find_ops.freeCommitSummaryList(std.testing.allocator, &list);

    try list.append(.{
        .commit_id = .{ .value = filled64('a') },
        .message = try std.testing.allocator.dupe(u8, "first"),
        .created_at = try std.testing.allocator.dupe(u8, "2026-03-10T00:00:00.000Z"),
        .local_created_at = try std.testing.allocator.dupe(u8, "2026-03-10T09:00:00.000+09:00"),
    });

    const output = try findResult(std.testing.allocator, &list, .{
        .tag = null,
        .empty_filter = .all,
        .since = null,
        .until = null,
        .since_millis = null,
        .until_millis = null,
        .limit = null,
        .output = .text,
        .fields = &.{ .commit_id, .created_at },
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 2026-03-10T09:00:00.000+09:00\n",
        output,
    );
}

test "findResult renders no commits message" {
    var list = find_ops.CommitSummaryList.init(std.testing.allocator);
    defer find_ops.freeCommitSummaryList(std.testing.allocator, &list);

    const output = try findResult(std.testing.allocator, &list, .{
        .tag = null,
        .empty_filter = .all,
        .since = null,
        .until = null,
        .since_millis = null,
        .until_millis = null,
        .limit = null,
        .output = .text,
        .fields = &.{},
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("no commits\n", output);
}

test "findResult renders since heading" {
    var list = find_ops.CommitSummaryList.init(std.testing.allocator);
    defer find_ops.freeCommitSummaryList(std.testing.allocator, &list);

    try list.append(.{
        .commit_id = .{ .value = filled64('a') },
        .message = try std.testing.allocator.dupe(u8, "first"),
        .created_at = try std.testing.allocator.dupe(u8, "2026-03-10T00:00:00.000Z"),
        .local_created_at = try std.testing.allocator.dupe(u8, "2026-03-10T09:00:00.000+09:00"),
    });

    const output = try findResult(std.testing.allocator, &list, .{
        .tag = null,
        .empty_filter = .all,
        .since = "2026-03-10",
        .until = null,
        .since_millis = 0,
        .until_millis = null,
        .limit = null,
        .output = .text,
        .fields = &.{},
    });
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.startsWith(u8, output, "Found 1 commit(s) since 2026-03-10.\n"));
}

test "findResult renders tag and range heading" {
    var list = find_ops.CommitSummaryList.init(std.testing.allocator);
    defer find_ops.freeCommitSummaryList(std.testing.allocator, &list);

    try list.append(.{
        .commit_id = .{ .value = filled64('a') },
        .message = try std.testing.allocator.dupe(u8, "first"),
        .created_at = try std.testing.allocator.dupe(u8, "2026-03-10T00:00:00.000Z"),
        .local_created_at = try std.testing.allocator.dupe(u8, "2026-03-10T09:00:00.000+09:00"),
    });

    const output = try findResult(std.testing.allocator, &list, .{
        .tag = "release",
        .empty_filter = .all,
        .since = "2026-03-10",
        .until = "2026-03-11",
        .since_millis = 0,
        .until_millis = 1,
        .limit = null,
        .output = .text,
        .fields = &.{},
    });
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.startsWith(u8, output, "Found 1 commit(s) for tag release from 2026-03-10 until 2026-03-11.\n"));
}

test "findResult renders json output" {
    var list = find_ops.CommitSummaryList.init(std.testing.allocator);
    defer find_ops.freeCommitSummaryList(std.testing.allocator, &list);

    try list.append(.{
        .commit_id = .{ .value = filled64('a') },
        .message = try std.testing.allocator.dupe(u8, "first"),
        .created_at = try std.testing.allocator.dupe(u8, "2026-03-10T00:00:00.000Z"),
        .local_created_at = try std.testing.allocator.dupe(u8, "2026-03-10T09:00:00.000+09:00"),
    });

    const output = try findResult(std.testing.allocator, &list, .{
        .tag = null,
        .empty_filter = .all,
        .since = null,
        .until = null,
        .since_millis = null,
        .until_millis = null,
        .limit = null,
        .output = .json,
        .fields = &.{},
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "[{\"commit_id\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"message\":\"first\",\"created_at\":\"2026-03-10T09:00:00.000+09:00\"}]",
        output,
    );
}

test "findResult renders selected fields as json" {
    var list = find_ops.CommitSummaryList.init(std.testing.allocator);
    defer find_ops.freeCommitSummaryList(std.testing.allocator, &list);

    try list.append(.{
        .commit_id = .{ .value = filled64('a') },
        .message = try std.testing.allocator.dupe(u8, "first"),
        .created_at = try std.testing.allocator.dupe(u8, "2026-03-10T00:00:00.000Z"),
        .local_created_at = try std.testing.allocator.dupe(u8, "2026-03-10T09:00:00.000+09:00"),
    });

    const output = try findResult(std.testing.allocator, &list, .{
        .tag = null,
        .empty_filter = .all,
        .since = null,
        .until = null,
        .since_millis = null,
        .until_millis = null,
        .limit = null,
        .output = .json,
        .fields = &.{.commit_id},
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "[{\"commit_id\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]",
        output,
    );
}

test "showResult renders readable commit details without internal ids" {
    var tz_guard = try local_time_text.testOnlyInitTimezoneGuard(std.testing.allocator, "Asia/Tokyo");
    defer tz_guard.deinit(std.testing.allocator);

    var details = try initTestCommitDetails(
        std.testing.allocator,
        filled64('a'),
        filled64('b'),
        "fix README.md",
        "2026-04-01T12:27:39.914Z",
    );
    defer show_ops.freeCommitDetails(std.testing.allocator, &details);

    try details.entries.append(.{
        .path = .{ .value = try std.testing.allocator.dupe(u8, "/Users/yoshidome/.vimrc") },
        .content_hash = .{ .value = filled64('c') },
    });
    try details.tags.append(try std.testing.allocator.dupe(u8, "tag1"));
    try details.tags.append(try std.testing.allocator.dupe(u8, "tag2"));

    const output = try showResult(std.testing.allocator, &details, .{
        .commit_id = details.commit_id.asSlice(),
        .output = .text,
        .fields = &.{},
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Found commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n" ++
            "2026-04-01T21:27:39.914+09:00\n\n" ++
            "fix README.md\n\n" ++
            "commit changes:\n" ++
            "- /Users/yoshidome/.vimrc\n" ++
            "tags:\n" ++
            "- tag1\n" ++
            "- tag2\n",
        output,
    );
    try std.testing.expect(std.mem.indexOf(u8, output, "snapshot") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "cccccccccccc") == null);
}

test "showResult renders empty tags as none" {
    var tz_guard = try local_time_text.testOnlyInitTimezoneGuard(std.testing.allocator, "Asia/Tokyo");
    defer tz_guard.deinit(std.testing.allocator);

    var details = try initTestCommitDetails(
        std.testing.allocator,
        filled64('d'),
        filled64('e'),
        "note",
        "2026-04-02T00:00:00.000Z",
    );
    defer show_ops.freeCommitDetails(std.testing.allocator, &details);

    try details.entries.append(.{
        .path = .{ .value = try std.testing.allocator.dupe(u8, "/tmp/a.txt") },
        .content_hash = .{ .value = filled64('f') },
    });

    const output = try showResult(std.testing.allocator, &details, .{
        .commit_id = details.commit_id.asSlice(),
        .output = .text,
        .fields = &.{},
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Found commit dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\n" ++
            "2026-04-02T09:00:00.000+09:00\n\n" ++
            "note\n\n" ++
            "commit changes:\n" ++
            "- /tmp/a.txt\n" ++
            "tags:\n" ++
            "- (none)\n",
        output,
    );
}

test "showResult renders selected fields as json" {
    var tz_guard = try local_time_text.testOnlyInitTimezoneGuard(std.testing.allocator, "Asia/Tokyo");
    defer tz_guard.deinit(std.testing.allocator);

    var details = try initTestCommitDetails(
        std.testing.allocator,
        filled64('a'),
        filled64('b'),
        "fix README.md",
        "2026-04-01T12:27:39.914Z",
    );
    defer show_ops.freeCommitDetails(std.testing.allocator, &details);

    try details.entries.append(.{
        .path = .{ .value = try std.testing.allocator.dupe(u8, "/tmp/a.txt") },
        .content_hash = .{ .value = filled64('c') },
    });

    const output = try showResult(std.testing.allocator, &details, .{
        .commit_id = details.commit_id.asSlice(),
        .output = .json,
        .fields = &.{ .created_at, .paths },
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "{\"created_at\":\"2026-04-01T21:27:39.914+09:00\",\"paths\":[\"/tmp/a.txt\"]}",
        output,
    );
}

test "showResult renders selected fields as text" {
    var details = try initTestCommitDetails(
        std.testing.allocator,
        filled64('a'),
        filled64('b'),
        "fix README.md",
        "2026-04-01T12:27:39.914Z",
    );
    defer show_ops.freeCommitDetails(std.testing.allocator, &details);

    try details.tags.append(try std.testing.allocator.dupe(u8, "tag1"));
    try details.tags.append(try std.testing.allocator.dupe(u8, "tag2"));

    const output = try showResult(std.testing.allocator, &details, .{
        .commit_id = details.commit_id.asSlice(),
        .output = .text,
        .fields = &.{ .commit_id, .tags },
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa tag1,tag2\n",
        output,
    );
}

test "statusResult groups staged, changed, and missing tracked files" {
    var list = status_ops.StatusList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(entry.path);
        list.deinit();
    }

    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/staged.txt"),
        .status = .staged,
    });
    try list.append(.{
        .id = .{ .value = filled32('b') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/changed.txt"),
        .status = .changed,
    });
    try list.append(.{
        .id = .{ .value = filled32('c') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/missing.txt"),
        .status = .missing,
    });

    const output = try statusResult(std.testing.allocator, &list, false);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "staged: /tmp/staged.txt\n" ++
            "changed: /tmp/changed.txt\n" ++
            "missing: /tmp/missing.txt\n" ++
            "Missing tracked files remain. Use `omohi untrack --missing` to clear them explicitly.\n",
        output,
    );
}

test "statusResult renders empty text when no tracked files changed" {
    var list = status_ops.StatusList.init(std.testing.allocator);
    defer list.deinit();

    const output = try statusResult(std.testing.allocator, &list, false);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("no staged, changed, or missing tracked files\n", output);
}

test "statusResult renders staged only" {
    var list = status_ops.StatusList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(entry.path);
        list.deinit();
    }

    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/staged.txt"),
        .status = .staged,
    });

    const output = try statusResult(std.testing.allocator, &list, false);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("staged: /tmp/staged.txt\n", output);
}

test "statusResult renders changed only" {
    var list = status_ops.StatusList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(entry.path);
        list.deinit();
    }

    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/changed.txt"),
        .status = .changed,
    });

    const output = try statusResult(std.testing.allocator, &list, false);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("changed: /tmp/changed.txt\n", output);
}

test "statusResult renders missing only with warning" {
    var list = status_ops.StatusList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(entry.path);
        list.deinit();
    }

    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/missing.txt"),
        .status = .missing,
    });

    const output = try statusResult(std.testing.allocator, &list, false);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "missing: /tmp/missing.txt\n" ++
            "Missing tracked files remain. Use `omohi untrack --missing` to clear them explicitly.\n",
        output,
    );
}

test "statusResult renders staged and changed without warning" {
    var list = status_ops.StatusList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(entry.path);
        list.deinit();
    }

    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/staged.txt"),
        .status = .staged,
    });
    try list.append(.{
        .id = .{ .value = filled32('b') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/changed.txt"),
        .status = .changed,
    });

    const output = try statusResult(std.testing.allocator, &list, false);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "staged: /tmp/staged.txt\n" ++
            "changed: /tmp/changed.txt\n",
        output,
    );
}

test "statusResult renders staged and missing with warning" {
    var list = status_ops.StatusList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(entry.path);
        list.deinit();
    }

    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/staged.txt"),
        .status = .staged,
    });
    try list.append(.{
        .id = .{ .value = filled32('b') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/missing.txt"),
        .status = .missing,
    });

    const output = try statusResult(std.testing.allocator, &list, false);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "staged: /tmp/staged.txt\n" ++
            "missing: /tmp/missing.txt\n" ++
            "Missing tracked files remain. Use `omohi untrack --missing` to clear them explicitly.\n",
        output,
    );
}

test "statusResult renders changed and missing with warning" {
    var list = status_ops.StatusList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(entry.path);
        list.deinit();
    }

    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/changed.txt"),
        .status = .changed,
    });
    try list.append(.{
        .id = .{ .value = filled32('b') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/missing.txt"),
        .status = .missing,
    });

    const output = try statusResult(std.testing.allocator, &list, false);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "changed: /tmp/changed.txt\n" ++
            "missing: /tmp/missing.txt\n" ++
            "Missing tracked files remain. Use `omohi untrack --missing` to clear them explicitly.\n",
        output,
    );
}

test "statusResult colors labels when enabled" {
    var list = status_ops.StatusList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(entry.path);
        list.deinit();
    }

    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/staged.txt"),
        .status = .staged,
    });
    try list.append(.{
        .id = .{ .value = filled32('b') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/changed.txt"),
        .status = .changed,
    });
    try list.append(.{
        .id = .{ .value = filled32('c') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/missing.txt"),
        .status = .missing,
    });

    const output = try statusResult(std.testing.allocator, &list, true);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "\x1b[32mstaged:\x1b[0m /tmp/staged.txt\n" ++
            "\x1b[31mchanged:\x1b[0m /tmp/changed.txt\n" ++
            "\x1b[90mmissing:\x1b[0m /tmp/missing.txt\n" ++
            "Missing tracked files remain. Use `omohi untrack --missing` to clear them explicitly.\n",
        output,
    );
}

test "untrackMissingResult renders bulk summary" {
    var outcome = track_ops.UntrackMissingOutcome.init(std.testing.allocator);
    defer track_ops.freeUntrackMissingOutcome(std.testing.allocator, &outcome);
    try outcome.untracked_paths.append(try std.testing.allocator.dupe(u8, "/tmp/a.txt"));
    try outcome.untracked_paths.append(try std.testing.allocator.dupe(u8, "/tmp/b.txt"));

    const output = try untrackMissingResult(std.testing.allocator, &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Untracked 2 missing tracked file(s).\n" ++
            "- /tmp/a.txt\n" ++
            "- /tmp/b.txt\n",
        output,
    );
}

test "untrackMissingResult renders no-op summary" {
    var outcome = track_ops.UntrackMissingOutcome.init(std.testing.allocator);
    defer track_ops.freeUntrackMissingOutcome(std.testing.allocator, &outcome);

    const output = try untrackMissingResult(std.testing.allocator, &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("No missing tracked files to untrack.\n", output);
}

test "tagAddResult renders no-new-tags branch with csv" {
    var tags = tag_ops.TagList.init(std.testing.allocator);
    defer {
        for (tags.items) |tag_name| std.testing.allocator.free(tag_name);
        tags.deinit();
    }

    try tags.append(try std.testing.allocator.dupe(u8, "mobile"));
    try tags.append(try std.testing.allocator.dupe(u8, "release"));

    const output = try tagAddResult(
        std.testing.allocator,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        0,
        &tags,
    );
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "No new tags were added; commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa already has the specified tags.\n" ++
            "mobile,release\n",
        output,
    );
}

test "tagAddResult renders added tags branch with csv" {
    var tags = tag_ops.TagList.init(std.testing.allocator);
    defer {
        for (tags.items) |tag_name| std.testing.allocator.free(tag_name);
        tags.deinit();
    }

    try tags.append(try std.testing.allocator.dupe(u8, "mobile"));
    try tags.append(try std.testing.allocator.dupe(u8, "release"));

    const output = try tagAddResult(
        std.testing.allocator,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        2,
        &tags,
    );
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Added 2 tag(s) to commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.\n" ++
            "mobile,release\n",
        output,
    );
}

test "tagNameListResult renders count and one tag per line" {
    var tags = tag_ops.TagNameList.init(std.testing.allocator);
    defer {
        for (tags.items) |tag_name| std.testing.allocator.free(tag_name);
        tags.deinit();
    }

    try tags.append(try std.testing.allocator.dupe(u8, "mobile"));
    try tags.append(try std.testing.allocator.dupe(u8, "release"));

    const output = try tagNameListResult(std.testing.allocator, &tags, &.{});
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Found 2 tag(s).\n" ++
            "mobile\n" ++
            "release\n",
        output,
    );
}

test "tagListResult renders count and one tag per line" {
    var tags = tag_ops.TagList.init(std.testing.allocator);
    defer {
        for (tags.items) |tag_name| std.testing.allocator.free(tag_name);
        tags.deinit();
    }

    try tags.append(try std.testing.allocator.dupe(u8, "mobile"));
    try tags.append(try std.testing.allocator.dupe(u8, "release"));

    const output = try tagListResult(
        std.testing.allocator,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        &tags,
        &.{},
    );
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Found 2 tag(s) for commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.\n" ++
            "mobile\n" ++
            "release\n",
        output,
    );
}

test "tagRmResult renders no-tags branch" {
    var tags = tag_ops.TagList.init(std.testing.allocator);
    defer tags.deinit();

    const output = try tagRmResult(
        std.testing.allocator,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        0,
        .no_tags,
        &tags,
    );
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa has no tags to remove.\n" ++
            "(none)\n",
        output,
    );
}

test "tagListResult renders none when no tags exist" {
    var tags = tag_ops.TagList.init(std.testing.allocator);
    defer tags.deinit();

    const output = try tagListResult(
        std.testing.allocator,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        &tags,
        &.{},
    );
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Found 0 tag(s) for commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.\n" ++
            "(none)\n",
        output,
    );
}

test "tagNameListResult renders none when no tags exist" {
    var tags = tag_ops.TagNameList.init(std.testing.allocator);
    defer tags.deinit();

    const output = try tagNameListResult(std.testing.allocator, &tags, &.{});
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Found 0 tag(s).\n" ++
            "(none)\n",
        output,
    );
}

test "tagNameListResult renders selected tag field only" {
    var tags = tag_ops.TagNameList.init(std.testing.allocator);
    defer {
        for (tags.items) |tag_name| std.testing.allocator.free(tag_name);
        tags.deinit();
    }

    try tags.append(try std.testing.allocator.dupe(u8, "mobile"));
    try tags.append(try std.testing.allocator.dupe(u8, "release"));

    const output = try tagNameListResult(std.testing.allocator, &tags, &.{.tag});
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "mobile\n" ++
            "release\n",
        output,
    );
}

test "tagListResult renders selected tag field only" {
    var tags = tag_ops.TagList.init(std.testing.allocator);
    defer {
        for (tags.items) |tag_name| std.testing.allocator.free(tag_name);
        tags.deinit();
    }

    try tags.append(try std.testing.allocator.dupe(u8, "mobile"));
    try tags.append(try std.testing.allocator.dupe(u8, "release"));

    const output = try tagListResult(
        std.testing.allocator,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        &tags,
        &.{.tag},
    );
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "mobile\n" ++
            "release\n",
        output,
    );
}

test "tag field output emits empty output for empty lists" {
    var global_tags = tag_ops.TagNameList.init(std.testing.allocator);
    defer global_tags.deinit();
    var commit_tags = tag_ops.TagList.init(std.testing.allocator);
    defer commit_tags.deinit();

    const global_output = try tagNameListResult(std.testing.allocator, &global_tags, &.{.tag});
    defer std.testing.allocator.free(global_output);
    try std.testing.expectEqualStrings("", global_output);

    const commit_output = try tagListResult(
        std.testing.allocator,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        &commit_tags,
        &.{.tag},
    );
    defer std.testing.allocator.free(commit_output);
    try std.testing.expectEqualStrings("", commit_output);
}

test "tagRmResult renders no-matching branch" {
    var tags = tag_ops.TagList.init(std.testing.allocator);
    defer {
        for (tags.items) |tag_name| std.testing.allocator.free(tag_name);
        tags.deinit();
    }

    try tags.append(try std.testing.allocator.dupe(u8, "mobile"));
    try tags.append(try std.testing.allocator.dupe(u8, "release"));

    const output = try tagRmResult(
        std.testing.allocator,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        0,
        .no_matching,
        &tags,
    );
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "No matching tags found to remove from commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.\n" ++
            "mobile,release\n",
        output,
    );
}

test "tagRmResult renders removed branch" {
    var tags = tag_ops.TagList.init(std.testing.allocator);
    defer {
        for (tags.items) |tag_name| std.testing.allocator.free(tag_name);
        tags.deinit();
    }

    try tags.append(try std.testing.allocator.dupe(u8, "release"));

    const output = try tagRmResult(
        std.testing.allocator,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        1,
        .removed,
        &tags,
    );
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Removed 1 tag(s) from commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.\n" ++
            "release\n",
        output,
    );
}

test "commitDryRunResult starts with migration message" {
    const entries = [_]CommitDryRunEntry{
        .{ .path = "/tmp/a.txt", .missing = false },
        .{ .path = "/tmp/b.txt", .missing = true },
    };
    const output = try commitDryRunResult(std.testing.allocator, entries.len, &entries);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Dry run: commit prepared but not written.\n" ++
            "dry-run staged count: 2\n" ++
            "- /tmp/a.txt\n" ++
            "- /tmp/b.txt (missing)\n",
        output,
    );
}
