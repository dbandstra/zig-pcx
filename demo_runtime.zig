const std = @import("std");
const pcx = @import("pcx.zig");

var mem: [1000 * 1024]u8 = undefined;
var gfa = std.heap.FixedBufferAllocator.init(&mem);

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

pub fn main() !void {
    const allocator = gfa.allocator();
    const stdout = std.io.getStdOut().writer();

    var file = try std.fs.cwd().openFile("testdata/space_merc.pcx", .{});
    defer file.close();
    const reader = file.reader();

    // load the image
    const preloaded = try pcx.preload(reader);
    const w: usize = preloaded.width;
    const h: usize = preloaded.height;
    const rgb = try allocator.alloc(u8, w * h * 3);
    defer allocator.free(rgb);
    try pcx.loadRGB(reader, preloaded, rgb);

    // print the image to the terminal, skipping every other row to
    // roughly accommodate the tall proportion of font characters
    var y: usize = 0;
    while (y < h) : (y += 2) {
        var x: usize = 0;
        while (x < w) : (x += 1) {
            const index = (y * w + x) * 3;
            try stdout.writeByte(grayscale(rgb[index..][0..3].*));
        }
        try stdout.writeByte('\n');
    }
}
