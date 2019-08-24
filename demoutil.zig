const std = @import("std");

pub fn convertToGreyscale(pixels: []const u8, output: []u8) void {
    std.debug.assert(pixels.len == output.len * 3);
    var i: usize = 0;
    while (i < output.len) : (i += 1) {
        const r = @intToFloat(f32, pixels[i*3+0]) / 255.0;
        const g = @intToFloat(f32, pixels[i*3+1]) / 255.0;
        const b = @intToFloat(f32, pixels[i*3+2]) / 255.0;
        const grey = 0.21 * r + 0.72 * g + 0.07 * b;
        output[i] = @floatToInt(u8, grey * 255);
    }
}

pub const grey10 = " .:-=+*#%@"; // http://paulbourke.net/dataformats/asciiart/
