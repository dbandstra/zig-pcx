// some basic tests, just to make sure well formed images are handled

const std = @import("std");
const MemoryOutStream = @import("../testutil.zig").MemoryOutStream;
const pcx = @import("../pcx.zig");

var mem: [1000 * 1024]u8 = undefined;
var gfa = std.heap.FixedBufferAllocator.init(mem[0..]);

fn test_load_comptime(
  comptime branch_quota: comptime_int,
  comptime basename: []const u8,
  comptime indexed: bool,
) void {
  comptime {
    @setEvalBranchQuota(branch_quota);

    const pcxfile = @embedFile("images/" ++ basename ++ ".pcx");
    var slice_stream = std.io.SliceStream.init(pcxfile);
    var stream = &slice_stream.stream;
    const Loader = pcx.Loader(std.io.SliceStream.Error);

    const preloaded = try Loader.preload(stream);
    const width = usize(preloaded.width);
    const height = usize(preloaded.height);

    if (indexed) {
      var pixels: [width * height]u8 = undefined;
      var palette: [768]u8 = undefined;
      try Loader.loadIndexed(stream, &preloaded, pixels[0..], palette[0..]);

      std.debug.assert(std.mem.eql(u8, pixels,
        @embedFile("images/" ++ basename ++ "-raw-indexed.data")));
      std.debug.assert(std.mem.eql(u8, palette,
        @embedFile("images/" ++ basename ++ "-raw-indexed.data.pal")));
    } else {
      var pixels: [width * height * 3]u8 = undefined;
      try Loader.loadRGB(stream, &preloaded, pixels[0..]);

      std.debug.assert(std.mem.eql(u8, pixels,
        @embedFile("images/" ++ basename ++ "-raw-r8g8b8.data")));
    }
  }
}

fn test_load_runtime(comptime basename: []const u8, indexed: bool) !void {
  defer gfa.end_index = 0;

  const pcxfile = @embedFile("images/" ++ basename ++ ".pcx");
  var slice_stream = std.io.SliceStream.init(pcxfile);
  var stream = &slice_stream.stream;
  const Loader = pcx.Loader(std.io.SliceStream.Error);

  const preloaded = try Loader.preload(stream);
  const width = usize(preloaded.width);
  const height = usize(preloaded.height);

  if (indexed) {
    var pixels = try gfa.allocator.alloc(u8, width * height);
    var palette: [768]u8 = undefined;
    try Loader.loadIndexed(stream, &preloaded, pixels, palette[0..]);

    std.debug.assert(std.mem.eql(u8, pixels,
      @embedFile("images/" ++ basename ++ "-raw-indexed.data")));
    std.debug.assert(std.mem.eql(u8, palette,
      @embedFile("images/" ++ basename ++ "-raw-indexed.data.pal")));
  } else {
    var rgb = try gfa.allocator.alloc(u8, width * height * 3);
    try Loader.loadRGB(stream, &preloaded, rgb);

    std.debug.assert(std.mem.eql(u8, rgb,
      @embedFile("images/" ++ basename ++ "-raw-r8g8b8.data")));
  }
}

test "load space_merc.pcx indexed comptime" {
  test_load_comptime(20000, "space_merc", true);
}

test "load space_merc.pcx rgb comptime" {
  test_load_comptime(20000, "space_merc", false);
}

test "load space_merc.pcx indexed runtime" {
  try test_load_runtime("space_merc", true);
}

test "load space_merc.pcx rgb runtime" {
  try test_load_runtime("space_merc", false);
}

// comptime loading is slow so skip these tests

test "load lena64.pcx indexed comptime" {
  if (true) return error.SkipZigTest;
  test_load_comptime(100000, "lena64", true);
}

test "load lena128.pcx indexed comptime" {
  if (true) return error.SkipZigTest;
  test_load_comptime(200000, "lena128", true);
}

test "load lena256.pcx indexed comptime" {
  if (true) return error.SkipZigTest;
  test_load_comptime(500000, "lena256", true);
}

// this one crashes after 20 seconds with the message "fork failed"
test "load lena512.pcx indexed comptime" {
  if (true) return error.SkipZigTest;
  test_load_comptime(20000000, "lena512", true);
}

test "load lena512.pcx indexed runtime" {
  try test_load_runtime("lena512", true);
}

test "load lena512.pcx rgb runtime" {
  try test_load_runtime("lena512", false);
}

// note: these resized lena images are not very useful for testing the loader
// (especially since they have even dimensions and as photos they are not
// suited for RLE), but they are useful for benchmarking, which i want to do
// eventually

test "load lena256.pcx indexed runtime" {
  try test_load_runtime("lena256", true);
}

test "load lena256.pcx rgb runtime" {
  try test_load_runtime("lena256", false);
}

test "load lena128.pcx indexed runtime" {
  try test_load_runtime("lena128", true);
}

test "load lena128.pcx rgb runtime" {
  try test_load_runtime("lena128", false);
}

test "load lena64.pcx indexed runtime" {
  try test_load_runtime("lena64", true);
}

test "load lena64.pcx rgb runtime" {
  try test_load_runtime("lena64", false);
}

fn test_save(comptime basename: []const u8, w: usize, h: usize) !void {
  const pcxfile = @embedFile("images/" ++ basename ++ ".pcx");

  var outbuf: [pcxfile.len]u8 = undefined;
  var mos = MemoryOutStream.init(outbuf[0..]);
  var stream = &mos.stream;
  const Saver = pcx.Saver(MemoryOutStream.WriteError);

  try Saver.saveIndexed(stream, w, h,
    @embedFile("images/" ++ basename ++ "-raw-indexed.data"),
    @embedFile("images/" ++ basename ++ "-raw-indexed.data.pal"));

  const result = mos.getSlice();

  std.debug.assert(
    std.mem.eql(u8, result[0..12], pcxfile[0..12]) and
    // skip hres, vres, reserved
    std.mem.eql(u8, result[65..70], pcxfile[65..70]) and
    // skip padding
    std.mem.eql(u8, result[128..], pcxfile[128..]),
  );
}

test "save space_merc.pcx comptime" {
  comptime {
    @setEvalBranchQuota(20000);
    try test_save("space_merc", 32, 32);
  }
}

test "save lena64.pcx comptime" {
  if (true) return error.SkipZigTest;
  comptime {
    @setEvalBranchQuota(100000);
    try test_save("lena64", 64, 64);
  }
}

test "save lena128.pcx comptime" {
  if (true) return error.SkipZigTest;
  comptime {
    @setEvalBranchQuota(500000);
    try test_save("lena128", 128, 128);
  }
}

// this one crashes with "fork failed"
test "save lena256.pcx comptime" {
  if (true) return error.SkipZigTest;
  comptime {
    @setEvalBranchQuota(2000000);
    try test_save("lena256", 256, 256);
  }
}

// haven't even tried this one
test "save lena512.pcx comptime" {
  if (true) return error.SkipZigTest;
  comptime {
    @setEvalBranchQuota(10000000);
    try test_save("lena512", 512, 512);
  }
}

test "save space_merc.pcx runtime" {
  try test_save("space_merc", 32, 32);
}

test "save lena64.pcx runtime" {
  try test_save("lena64", 64, 64);
}

test "save lena128.pcx runtime" {
  try test_save("lena128", 128, 128);
}

test "save lena256.pcx runtime" {
  try test_save("lena256", 256, 256);
}

test "save lena512.pcx runtime" {
  try test_save("lena512", 512, 512);
}
