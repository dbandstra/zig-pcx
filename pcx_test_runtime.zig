const std = @import("std");
const pcx = @import("pcx.zig");
const util = @import("testutil.zig");

test "load pcx at run time" {
  const allocator = std.debug.global_allocator;
  var file = try std.os.File.openRead(allocator, "test/images/space_merc.pcx");
  defer file.close();
  var file_stream = std.io.FileInStream.init(&file);
  var stream = &file_stream.stream;
  const Loader = pcx.Loader(std.io.FileInStream.Error);
  const preloaded = try Loader.preload(stream);
  var rgb = try allocator.alloc(u8, preloaded.width * preloaded.height * 3);
  try Loader.loadIntoRGB(stream, &preloaded, rgb[0..]);
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
  std.debug.warn("{}\n", string);
}
