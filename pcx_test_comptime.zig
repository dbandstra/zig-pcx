const std = @import("std");
const pcx = @import("pcx.zig");
const util = @import("testutil.zig");

test "load pcx at compile time" {
  comptime {
    @setEvalBranchQuota(20000);

    const input = @embedFile("test/images/space_merc.pcx");
    var slice_stream = std.io.SliceStream.init(input);
    var stream = &slice_stream.stream;
    const Loader = pcx.Loader(std.io.SliceStream.Error);
    const preloaded = try Loader.preload(stream);
    var rgb: [preloaded.width * preloaded.height * 3]u8 = undefined;
    try Loader.loadIntoRGB(stream, &preloaded, rgb[0..]);

    var greyscale: [preloaded.width * preloaded.height]u8 = undefined;
    util.convertToGreyscale(rgb, greyscale[0..]);
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
    @compileLog(string);
  }
}
