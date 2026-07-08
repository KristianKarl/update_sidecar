# Project Functional Description

## Purpose

Modify XMP sidecar files to work around a limitation in Immich.

## Background

- **digikam** uses **exiftool** to write XMP sidecar files (`.xmp`) alongside image files.
- These sidecar files contain metadata fields including `Title` and `Description`.
- **Immich** reads these sidecar files but **does not read the `Title` field**.
- As a result, any title set in digikam is invisible in Immich.

## Task

The program shall:

1. Accept a **directory path** as the sole CLI argument.
2. **Recursively** walk the directory and find all `.xmp` files.
3. For each `.xmp` file, parse it to find the `Title` field (typically `<dc:title>` with an `rdf:Alt` / `rdf:li` element).
4. If a non-empty `Title` exists, copy its value into the `Description` field (typically `<dc:description>`).
   - **Append** the title to any existing description content as `"<existing>\n\nTitle: <title>"`.
   - If no description exists, just set it to the title value.
5. **Back up** the original file by copying it with a `.orig` suffix before writing the updated version.
6. Preserve all other metadata fields exactly.
7. When the program completes, it shall print statistics on how many files were changed, or not changed.

## Verification

Unit tests in `src/sidecar.zig` cover these scenarios:

1. **Title extraction** — parses title from `<dc:title>` block; returns null when absent
2. **Description extraction** — parses description from `<dc:description>` block; returns null when absent
3. **Update existing description** — appends `"\n\nTitle: <title>"` when a description already exists
4. **Insert new description** — creates a `<dc:description>` block when none exists
5. **Idempotency** — returns no-change when the title is already present in the description
6. **Preserve other metadata** — fields like `<dc:subject>` and `<xmp:Rating>` are left untouched

Run with `zig build test`.