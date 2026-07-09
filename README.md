# update_sidecar

Built by [krikar](https://github.com/KristianKarl) and [opencode](https://opencode.ai).

Modifies XMP sidecar files to work around a limitation in Immich.

## Background

- **digikam** uses **exiftool** to write XMP sidecar files (`.xmp`) alongside image files.
- These sidecar files contain metadata fields including `Title` and `Description`.
- **Immich** reads these sidecar files but **does not read the `Title` field**.
- As a result, any title set in digikam is invisible in Immich.

## Usage

```sh
zig build run -- <directory>
```

Recursively walks `<directory>`, finds all `.xmp` files, and for each one:

1. Extracts the `Title` field.
2. Copies it into the `Description` field (appending if a description already exists).
3. Backs up the original file with a `.orig` suffix before writing the updated version.

## Development

The project uses the `0.16.0` version of zig.

```sh
zig build test   # run tests
zig build run    # run the program on the current directory
```

## Build production binary

```sh
zig build -Doptimize=ReleaseFast  # builds the optimized binary
```
