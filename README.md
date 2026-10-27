# update_sidecar

Built by [Kristian Karl](https://github.com/KristianKarl) and [opencode](https://opencode.ai).

Modifies XMP sidecar files to work around a limitation in Immich.

## Background

- **digikam** uses **exiftool** to write XMP sidecar files (`.xmp`) alongside image files.
- These sidecar files contain metadata fields including `Title` and `Description`.
- **Immich** reads these sidecar files but **does not read the `Title` field**.
- As a result, any title set in digikam is invisible in Immich.

## Usage

```sh
zig build run -- <directory>
zig build run -- --help       # show detailed usage, options, and safety notes
zig build run -- --version    # show the version and build commit SHA
```

The directory defaults to the current directory when omitted. Use `--help` or
`-h` instead of a directory to print help without processing any files. There
are no subcommands. Use `--version` instead of a directory to print the version,
for example `update_sidecar 1.0.2 (a1b2c3d)`, without processing files.

The version number comes from `build.zig.zon`. The abbreviated Git SHA is embedded
at build time, so Git and a repository checkout are required to build, but not to
run the binary.

Recursively walks `<directory>`, finds all `.xmp` files, and for each one:

1. Extracts the `Title` field.
2. Copies it into the `Description` field (appending if a description already exists).
3. Backs up the original file with a `.orig` suffix before writing the updated version.

**Warning:** An existing `.orig` backup is overwritten if that sidecar is updated
again. There is no dry-run mode; keep a separate backup of important metadata.

## Development

The project uses the `0.17.0` version of Zig.

```sh
zig build test   # run tests
zig build run    # run the program on the current directory
```

## Build production binary

```sh
zig build -Doptimize=ReleaseFast  # builds the optimized binary
```
