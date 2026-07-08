pub const processFile = @import("sidecar.zig").processFile;
pub const ProcessResult = @import("sidecar.zig").ProcessResult;

test {
    _ = processFile;
    _ = ProcessResult;
}
