const std = @import("std");
const sidecar = @import("update_sidecar");

const help =
    \\update_sidecar - Make XMP sidecar titles visible in Immich.
    \\
    \\USAGE
    \\  update_sidecar [DIRECTORY]
    \\  update_sidecar --help
    \\  update_sidecar -h
    \\
    \\ARGUMENTS
    \\  DIRECTORY   Directory to search recursively. Defaults to the current
    \\              directory (.). Quote paths that contain spaces.
    \\
    \\OPTIONS
    \\  -h, --help  Print this help and exit without reading or changing sidecars.
    \\              Use this option in place of DIRECTORY.
    \\
    \\SUBCOMMANDS
    \\  None. Running the program processes sidecars immediately.
    \\
    \\HOW IT WORKS
    \\  Finds files with a .xmp extension (case-insensitive) in DIRECTORY and its
    \\  subdirectories. Reads the first rdf:li value in each dc:title block.
    \\  If dc:description exists, appends a blank line followed by "Title: TITLE".
    \\  Otherwise, inserts a dc:description block containing the title.
    \\  Files with no title or an empty title are skipped. Files whose description
    \\  already contains the title are left unchanged.
    \\
    \\BACKUPS AND SAFETY
    \\  Before modifying a sidecar, copies it to the same directory with .orig
    \\  appended to its filename (for example, photo.xmp.orig).
    \\  WARNING: An existing .orig backup is overwritten on a subsequent update.
    \\  Image files are not changed. Symbolic links are not followed.
    \\  Sidecars larger than 10 MiB cannot be processed.
    \\  There is no dry-run mode; keep a separate backup of important metadata.
    \\
    \\OUTPUT
    \\  Reports updated and skipped files, individual file errors, and a final
    \\  count of sidecars checked and updated. Processing continues after an
    \\  individual file error. These messages go to standard error; help goes
    \\  to standard output.
    \\
    \\EXAMPLES
    \\  update_sidecar
    \\      Process sidecars under the current directory.
    \\  update_sidecar /path/to/photos
    \\      Process sidecars under a specific directory.
    \\  update_sidecar "/path/to/My Photos"
    \\      Process a directory whose path contains spaces.
    \\  update_sidecar ./--help
    \\      Process a directory literally named --help.
    \\  zig 0.17.0 build run -- --help
    \\      Show program help through the Zig build system.
    \\  zig 0.17.0 build run -- /path/to/photos
    \\      Build and run the program on a specific directory.
    \\  ./zig-out/bin/update_sidecar --help
    \\      Show help from the binary installed by zig build.
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);

    const dir_path = if (args.len > 1) args[1] else ".";
    if (std.mem.eql(u8, dir_path, "--help") or std.mem.eql(u8, dir_path, "-h")) {
        try std.Io.File.stdout().writeStreamingAll(io, help);
        return;
    }

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
