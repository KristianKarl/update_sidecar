const std = @import("std");
const sidecar = @import("update_sidecar");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);

    const dir_path = if (args.len > 1) args[1] else ".";
    const root_dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{
        .access_sub_paths = true,
        .iterate = true,
        .follow_symlinks = false,
    });
    defer root_dir.close(io);

    var walker = try root_dir.walk(arena);
    defer walker.deinit();

    var checked_count: u32 = 0;
    var updated_count: u32 = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const ext = std.fs.path.extension(entry.basename);
        if (!std.ascii.eqlIgnoreCase(ext, ".xmp")) continue;
        checked_count += 1;

        const result = sidecar.processFile(io, arena, entry.dir, entry.basename) catch |err| {
            std.debug.print("error: {s}/{s}: {}\n", .{ dir_path, entry.path, err });
            continue;
        };
        switch (result) {
            .updated => {
                std.debug.print("updated: {s}/{s}\n", .{ dir_path, entry.path });
                updated_count += 1;
            },
            .no_title => std.debug.print("skipped: {s}/{s} (no title)\n", .{ dir_path, entry.path }),
            .no_change => std.debug.print("skipped: {s}/{s} (title already in description)\n", .{ dir_path, entry.path }),
        }
    }

    std.debug.print("done — {d} checked, {d} updated\n", .{ checked_count, updated_count });
}
