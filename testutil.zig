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

pub const MemoryOutStream = struct {
  buffer: []u8,
  index: usize,
  stream: Stream,

  pub const WriteError = error{OutOfSpace};
  pub const Stream = std.io.OutStream(WriteError);

  pub fn init(buffer: []u8) MemoryOutStream {
    return MemoryOutStream{
      .buffer = buffer,
      .index = 0,
      .stream = Stream{ .writeFn = writeFn },
    };
  }

  // no deinit function.

  pub fn getSlice(self: *const MemoryOutStream) []const u8 {
    return self.buffer[0..self.index];
  }

  pub fn reset(self: *MemoryOutStream) void {
    self.index = 0;
  }

  fn writeFn(out_stream: *Stream, bytes: []const u8) WriteError!void {
    if (bytes.len == 0) {
      return;
    }

    const self = @fieldParentPtr(MemoryOutStream, "stream", out_stream);

    var num_bytes_to_copy = bytes.len;
    var not_enough_space = false;

    if (self.index + num_bytes_to_copy > self.buffer.len) {
      num_bytes_to_copy = self.buffer.len - self.index;
      not_enough_space = true;
    }

    std.mem.copy(u8, self.buffer[self.index..self.index + num_bytes_to_copy], bytes[0..num_bytes_to_copy]);
    self.index += num_bytes_to_copy;

    if (not_enough_space) {
      return WriteError.OutOfSpace;
    }
  }
};
