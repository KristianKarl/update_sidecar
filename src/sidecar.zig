const std = @import("std");

pub const ProcessResult = enum {
    updated,
    no_title,
    no_change,
};

pub fn processFile(
    io: std.Io,
    allocator: std.mem.Allocator,
    file_dir: std.Io.Dir,
    filename: []const u8,
) !ProcessResult {
    const limit: std.Io.Limit = @fromBackingInt(@intCast(10 * 1024 * 1024));
    const content = try file_dir.readFileAlloc(io, filename, allocator, limit);
    defer allocator.free(content);

    const title = extractTitle(content) orelse return .no_title;
    const trimmed_title = std.mem.trim(u8, title, " \t\n\r");
    if (trimmed_title.len == 0) return .no_title;

    const new_content = try updateDescription(allocator, content, trimmed_title) orelse return .no_change;

    if (std.mem.eql(u8, content, new_content)) return .no_change;

    const backup_name = try std.fmt.allocPrint(allocator, "{s}.orig", .{filename});
    defer allocator.free(backup_name);
    try file_dir.copyFile(filename, file_dir, backup_name, io, .{
        .permissions = null,
        .make_path = false,
        .replace = true,
    });

    try file_dir.writeFile(io, .{
        .sub_path = filename,
        .data = new_content,
        .flags = .{},
    });

    return .updated;
}

fn extractTitle(content: []const u8) ?[]const u8 {
    const block = extractBlock(content, "dc:title") orelse return null;
    return extractRdfLiValue(block);
}

fn extractDescription(content: []const u8) ?[]const u8 {
    const block = extractBlock(content, "dc:description") orelse return null;
    return extractRdfLiValue(block);
}

fn extractBlock(content: []const u8, tag: []const u8) ?[]const u8 {
    var open_buf: [64]u8 = undefined;
    const open_tag = std.fmt.bufPrint(&open_buf, "<{s}", .{tag}) catch return null;
    const open_start = std.mem.indexOf(u8, content, open_tag) orelse return null;
    const after_open = content[open_start..];
    const gt = std.mem.indexOfScalar(u8, after_open, '>') orelse return null;
    const block_start = open_start + gt + 1;

    var close_buf: [64]u8 = undefined;
    const close_tag = std.fmt.bufPrint(&close_buf, "</{s}>", .{tag}) catch return null;
    const block_end = std.mem.indexOf(u8, content[block_start..], close_tag) orelse return null;

    return content[block_start..][0..block_end];
}

fn extractRdfLiValue(block: []const u8) ?[]const u8 {
    const li_start = std.mem.indexOf(u8, block, "<rdf:li") orelse return null;
    const after_li = block[li_start..];
    const gt = std.mem.indexOfScalar(u8, after_li, '>') orelse return null;
    const value_start = li_start + gt + 1;
    const li_close = std.mem.indexOf(u8, block[value_start..], "</rdf:li>") orelse return null;
    const value = block[value_start..][0..li_close];
    return std.mem.trim(u8, value, " \t\n\r");
}

fn updateDescription(allocator: std.mem.Allocator, content: []const u8, title: []const u8) !?[]u8 {
    const desc_value = extractDescription(content);
    if (desc_value) |existing| {
        const trimmed_existing = std.mem.trim(u8, existing, " \t\n\r");
        if (std.mem.indexOf(u8, trimmed_existing, title) != null) return null;

        const new_desc_value = try std.fmt.allocPrint(allocator, "{s}\n\nTitle: {s}", .{ trimmed_existing, title });
        defer allocator.free(new_desc_value);
        return replaceDescriptionValue(allocator, content, existing, new_desc_value);
    }
    return insertDescriptionBlock(allocator, content, title);
}

fn replaceDescriptionValue(
    allocator: std.mem.Allocator,
    content: []const u8,
    old_value: []const u8,
    new_value: []const u8,
) !?[]u8 {
    var open_buf: [64]u8 = undefined;
    const open_tag = std.fmt.bufPrint(&open_buf, "<dc:description", .{}) catch return null;
    const block_start = std.mem.indexOf(u8, content, open_tag) orelse return null;
    const after_open = content[block_start..];
    const gt = std.mem.indexOfScalar(u8, after_open, '>') orelse return null;
    const search_start = block_start + gt + 1;

    const close_tag = "</dc:description>";
    const block_end = std.mem.indexOf(u8, content[search_start..], close_tag) orelse return null;
    const inner_end = search_start + block_end;

    const inner = content[search_start..inner_end];
    const value_pos = std.mem.indexOf(u8, inner, old_value) orelse return null;
    const abs_pos = search_start + value_pos;

    var result = try std.ArrayList(u8).initCapacity(allocator, content.len + (new_value.len -| old_value.len));
    try result.appendSlice(allocator, content[0..abs_pos]);
    try result.appendSlice(allocator, new_value);
    try result.appendSlice(allocator, content[abs_pos + old_value.len ..]);
    return @as(?[]u8, try result.toOwnedSlice(allocator));
}

fn insertDescriptionBlock(allocator: std.mem.Allocator, content: []const u8, value: []const u8) !?[]u8 {
    const insert_pos = blk: {
        if (std.mem.indexOf(u8, content, "</dc:title>")) |pos| {
            break :blk pos + "</dc:title>".len;
        }
        if (std.mem.indexOf(u8, content, "</dc:subject>")) |pos| {
            break :blk pos + "</dc:subject>".len;
        }
        if (std.mem.indexOf(u8, content, "</rdf:Description>")) |pos| {
            break :blk pos;
        }
        return null;
    };

    const block = try std.fmt.allocPrint(allocator,
        \\      <dc:description>
        \\        <rdf:Alt>
        \\          <rdf:li xml:lang="x-default">{s}</rdf:li>
        \\        </rdf:Alt>
        \\      </dc:description>
    , .{value});
    defer allocator.free(block);

    var result = try std.ArrayList(u8).initCapacity(allocator, content.len + 1 + block.len);
    try result.appendSlice(allocator, content[0..insert_pos]);
    try result.appendSlice(allocator, "\n");
    try result.appendSlice(allocator, block);
    try result.appendSlice(allocator, content[insert_pos..]);
    return @as(?[]u8, try result.toOwnedSlice(allocator));
}

const testing = std.testing;

test "extractTitle returns value from dc:title block" {
    const xmp =
        \\<rdf:Description>
        \\  <dc:title>
        \\    <rdf:Alt>
        \\      <rdf:li xml:lang="x-default">My Title</rdf:li>
        \\    </rdf:Alt>
        \\  </dc:title>
        \\</rdf:Description>
    ;
    const result = extractTitle(xmp);
    try testing.expectEqualStrings("My Title", result.?);
}

test "extractTitle returns null when no dc:title" {
    const xmp =
        \\<rdf:Description>
        \\  <dc:description>
        \\    <rdf:Alt>
        \\      <rdf:li xml:lang="x-default">Desc</rdf:li>
        \\    </rdf:Alt>
        \\  </dc:description>
        \\</rdf:Description>
    ;
    try testing.expect(extractTitle(xmp) == null);
}

test "extractDescription returns value from dc:description block" {
    const xmp =
        \\<rdf:Description>
        \\  <dc:description>
        \\    <rdf:Alt>
        \\      <rdf:li xml:lang="x-default">Some desc</rdf:li>
        \\    </rdf:Alt>
        \\  </dc:description>
        \\</rdf:Description>
    ;
    const result = extractDescription(xmp);
    try testing.expectEqualStrings("Some desc", result.?);
}

test "extractDescription returns null when no dc:description" {
    const xmp =
        \\<rdf:Description>
        \\  <dc:title>
        \\    <rdf:Alt>
        \\      <rdf:li xml:lang="x-default">Title</rdf:li>
        \\    </rdf:Alt>
        \\  </dc:title>
        \\</rdf:Description>
    ;
    try testing.expect(extractDescription(xmp) == null);
}

test "updateDescription appends title to existing description" {
    const allocator = testing.allocator;
    const content =
        \\<rdf:Description>
        \\  <dc:title>
        \\    <rdf:Alt>
        \\      <rdf:li xml:lang="x-default">My Title</rdf:li>
        \\    </rdf:Alt>
        \\  </dc:title>
        \\  <dc:description>
        \\    <rdf:Alt>
        \\      <rdf:li xml:lang="x-default">Original desc</rdf:li>
        \\    </rdf:Alt>
        \\  </dc:description>
        \\</rdf:Description>
    ;
    const result = (try updateDescription(allocator, content, "My Title")).?;
    defer allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "Original desc\n\nTitle: My Title") != null);
}

test "updateDescription inserts new block when no description" {
    const allocator = testing.allocator;
    const content =
        \\<rdf:Description>
        \\  <dc:title>
        \\    <rdf:Alt>
        \\      <rdf:li xml:lang="x-default">My Title</rdf:li>
        \\    </rdf:Alt>
        \\  </dc:title>
        \\</rdf:Description>
    ;
    const result = (try updateDescription(allocator, content, "My Title")).?;
    defer allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "<dc:description>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "My Title") != null);
}

test "updateDescription returns null when title already in description" {
    const allocator = testing.allocator;
    const content =
        \\<rdf:Description>
        \\  <dc:title>
        \\    <rdf:Alt>
        \\      <rdf:li xml:lang="x-default">My Title</rdf:li>
        \\    </rdf:Alt>
        \\  </dc:title>
        \\  <dc:description>
        \\    <rdf:Alt>
        \\      <rdf:li xml:lang="x-default">Some text\n\nTitle: My Title</rdf:li>
        \\    </rdf:Alt>
        \\  </dc:description>
        \\</rdf:Description>
    ;
    try testing.expect((try updateDescription(allocator, content, "My Title")) == null);
}

test "updateDescription does not modify other metadata" {
    const allocator = testing.allocator;
    const content =
        \\<rdf:Description>
        \\  <dc:title>
        \\    <rdf:Alt>
        \\      <rdf:li xml:lang="x-default">Title</rdf:li>
        \\    </rdf:Alt>
        \\  </dc:title>
        \\  <dc:subject>
        \\    <rdf:Bag>
        \\      <rdf:li>tag1</rdf:li>
        \\    </rdf:Bag>
        \\  </dc:subject>
        \\  <dc:description>
        \\    <rdf:Alt>
        \\      <rdf:li xml:lang="x-default">Desc</rdf:li>
        \\    </rdf:Alt>
        \\  </dc:description>
        \\  <xmp:Rating>3</xmp:Rating>
        \\</rdf:Description>
    ;
    const result = (try updateDescription(allocator, content, "Title")).?;
    defer allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "<dc:subject>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "tag1") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<xmp:Rating>3</xmp:Rating>") != null);
}
