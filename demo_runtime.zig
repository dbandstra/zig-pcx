const std = @import("std");
const pcx = @import("pcx.zig");
const util = @import("demoutil.zig");

pub fn main() !void {
    const allocator = std.testing.allocator;
    var file = try std.fs.cwd().openFile("testdata/space_merc.pcx", .{});
    defer file.close();
    var stream = std.fs.File.inStream(file);
    const Loader = pcx.Loader(@TypeOf(stream));
    const preloaded = try Loader.preload(&stream);
    var rgb = try allocator.alloc(u8, preloaded.width * preloaded.height * 3);
    try Loader.loadRGB(&stream, preloaded, rgb);
    defer allocator.free(rgb);

    var greyscale = try allocator.alloc(u8, preloaded.width * preloaded.height);
    defer allocator.free(greyscale);
    util.convertToGreyscale(rgb, greyscale[0..]);
    var string = try allocator.alloc(u8, (preloaded.width+1)*preloaded.height);
    defer allocator.free(string);
    var i: usize = 0;
    var y: usize = 0;
    while (y < preloaded.height) : (y += 1) {
        string[i] = '\n'; i += 1;
        var x: usize = 0;
        while (x < preloaded.width) : (x += 1) {
            const shade256 = greyscale[y*preloaded.width+x];
            const quant = @divFloor(shade256, 26);
            string[i] = util.grey10[9 - quant]; i += 1;
        }
    }
    std.debug.warn("{}\n", .{string});
}
