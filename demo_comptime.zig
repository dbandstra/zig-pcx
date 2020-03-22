const std = @import("std");
const pcx = @import("pcx.zig");
const util = @import("demoutil.zig");

pub fn main() void {
    comptime {
        @setEvalBranchQuota(20000);

        const input = @embedFile("testdata/space_merc.pcx");
        var stream = std.io.fixedBufferStream(input).inStream();
        const Loader = pcx.Loader(@TypeOf(stream));
        const preloaded = try Loader.preload(&stream);
        var rgb: [preloaded.width * preloaded.height * 3]u8 = undefined;
        try Loader.loadRGB(&stream, preloaded, &rgb);

        var greyscale: [preloaded.width * preloaded.height]u8 = undefined;
        util.convertToGreyscale(&rgb, &greyscale);
        var string: [(preloaded.width+1)*preloaded.height]u8 = undefined;
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
        @compileError(&string);
    }
}
