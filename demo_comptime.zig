const std = @import("std");
const pcx = @import("pcx.zig");

const grey10 = " .:-=+*#%@"; // http://paulbourke.net/dataformats/asciiart/

fn grayscale(pixel: [3]u8) u8 {
    const r = @as(f32, @floatFromInt(pixel[0])) / 255.0;
    const g = @as(f32, @floatFromInt(pixel[1])) / 255.0;
    const b = @as(f32, @floatFromInt(pixel[2])) / 255.0;
    const grey = 0.21 * r + 0.72 * g + 0.07 * b;
    const shade256: u8 = @intFromFloat(grey * 255);
    const quant = @divFloor(shade256, 26);
    return grey10[9 - quant];
}

pub fn main() void {
    comptime {
        @setEvalBranchQuota(20000);

        const input = @embedFile("testdata/space_merc.pcx");
        var fbs = std.io.fixedBufferStream(input);
        var reader = fbs.reader();

        // load the image
        const preloaded = try pcx.preload(reader);
        const w: usize = preloaded.width;
        const h: usize = preloaded.height;
        var rgb: [w * h * 3]u8 = undefined;
        try pcx.loadRGB(reader, preloaded, &rgb);

        // convert the image to an ASCII string, skipping every other row to
        // roughly accommodate the tall proportion of font characters. add
        // one to the width to fit newline characters
        var ascii: [(w + 1) * (h / 2)]u8 = undefined;

        var i: usize = 0;
        var y: usize = 0;
        while (y < h) : (y += 2) {
            ascii[i] = '\n';
            i += 1;
            var x: usize = 0;
            while (x < w) : (x += 1) {
                const index = (y * w + x) * 3;
                ascii[i] = grayscale(rgb[index..][0..3].*);
                i += 1;
            }
        }

        // print the image as a compile error
        @compileError(&ascii);
    }
}
