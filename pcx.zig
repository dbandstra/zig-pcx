const std = @import("std");

pub const PreloadedInfo = struct {
  width: u16,
  height: u16,
  bytes_per_line: u16,
};

pub fn Loader(comptime ReadError: type) type {
  return struct {
    const Self = this;

    pub fn preload(stream: *std.io.InStream(ReadError)) !PreloadedInfo {
      var header: [70]u8 = undefined;
      _ = try stream.readNoEof(header[0..]);
      try stream.skipBytes(58);
      const manufacturer = header[0];
      const version = header[1];
      if (manufacturer != 0x0a or version != 5) {
        return error.PcxLoadFailed;
      }
      const encoding = header[2];
      const bits_per_pixel = header[3];
      const xmin = u16(header[4]) | (u16(header[5]) << 8);
      const ymin = u16(header[6]) | (u16(header[7]) << 8);
      const xmax = u16(header[8]) | (u16(header[9]) << 8);
      const ymax = u16(header[10]) | (u16(header[11]) << 8);
      const hres = u16(header[12]) | (u16(header[13]) << 8);
      const vres = u16(header[14]) | (u16(header[15]) << 8);
      const reserved = header[64];
      const color_planes = header[65];
      const bytes_per_line = u16(header[66]) | (u16(header[67]) << 8);
      const palette_type = u16(header[68]) | (u16(header[69]) << 8);
      if (encoding != 1 or
          bits_per_pixel != 8 or
          xmin > xmax or
          ymin > ymax or
          color_planes != 1) {
        return error.PcxLoadFailed;
      }
      return PreloadedInfo{
        .width = xmax - xmin + 1,
        .height = ymax - ymin + 1,
        .bytes_per_line = bytes_per_line,
      };
    }

    pub fn loadIndexed(
      stream: *std.io.InStream(ReadError),
      preloaded: *const PreloadedInfo,
      out_buffer: []u8,
      out_palette: []u8,
    ) !void {
      try loadIndexedWithStride(stream, preloaded, out_buffer, 1, out_palette);
    }

    pub fn loadIndexedWithStride(
      stream: *std.io.InStream(ReadError),
      preloaded: *const PreloadedInfo,
      out_buffer: []u8,
      out_buffer_stride: usize,
      out_palette: []u8,
    ) !void {
      var input_buffer: [128]u8 = undefined;
      var input = input_buffer[0..0];

      if (out_buffer_stride < 1) {
        return error.PcxLoadFailed;
      }
      if (out_palette.len < 768) {
        return error.PcxLoadFailed;
      }
      const width = usize(preloaded.width);
      const height = usize(preloaded.height);
      const datasize = width * height * out_buffer_stride;
      if (out_buffer.len < datasize) {
        return error.PcxLoadFailed;
      }

      // load image data (1 byte per pixel)
      var in: usize = 0;
      var out: usize = 0;
      var runlen: u8 = undefined;
      var y: u16 = 0;
      while (y < height) : (y += 1) {
        var x: u16 = 0;
        while (x < preloaded.bytes_per_line) {
          var databyte = blk: {
            if (in >= input.len) {
              const n = try stream.read(input_buffer[0..]);
              if (n == 0) {
                return error.EndOfStream;
              }
              input = input_buffer[0..n];
              in = 0;
            }
            defer in += 1;
            break :blk input[in];
          };
          if ((databyte & 0xc0) == 0xc0) {
            runlen = databyte & 0x3f;
            databyte = blk: {
              if (in >= input.len) {
                const n = try stream.read(input_buffer[0..]);
                if (n == 0) {
                  return error.EndOfStream;
                }
                input = input_buffer[0..n];
                in = 0;
              }
              defer in += 1;
              break :blk input[in];
            };
          } else {
            runlen = 1;
          }
          while (runlen > 0) {
            runlen -= 1;
            if (x < width) {
              if (out >= datasize) {
                return error.PcxLoadFailed;
              }
              out_buffer[out] = databyte;
              out += out_buffer_stride;
            }
            x += 1;
          }
        }
      }
      if (out != datasize) {
        return error.PcxLoadFailed;
      }

      // load palette... this occupies the last 768 bytes of the file. because
      // there is no seeking, use a buffering scheme to recover the palette
      // once we actually hit the end of the file.
      // note: palette is supposed to be preceded by a 0x0C marker byte, but
      // i've dealt with images that didn't have it so i won't assume it's
      // there
      var page_bufs: [2][768]u8 = undefined;
      var pages: [2][]u8 = undefined;
      var which_page: u8 = 0;
      while (true) {
        var n: usize = 0;
        if (in < input.len) {
          // some left over buffered data from the image data loading (this
          // will only happen on the first iteration)
          n = input.len - in;
          std.mem.copy(u8, page_bufs[which_page][0..n], input[in..]);
          in = input.len;
        }
        n += try stream.read(page_bufs[which_page][n..]);
        pages[which_page] = page_bufs[which_page][0..n];
        if (n < 768) {
          // reached EOF
          if (n == 0) {
            which_page ^= 1;
          }
          break;
        }
        which_page ^= 1;
      }
      if (pages[0].len + pages[1].len < 768) {
        return error.PcxLoadFailed;
      }
      // the palette will either be completely contained in the current page;
      // or else its first part will be in the opposite page, and the rest in
      // the current page
      const cur_page = pages[which_page];
      const opp_page = pages[which_page ^ 1];
      const cur_len = cur_page.len;
      const opp_len = 768 - cur_len;
      std.mem.copy(u8, out_palette[0..opp_len], opp_page[cur_len..768]);
      std.mem.copy(u8, out_palette[opp_len..768], cur_page);
    }

    pub fn loadRGB(
      stream: *std.io.InStream(ReadError),
      preloaded: *const PreloadedInfo,
      out_buffer: []u8,
    ) !void {
      const num_pixels = usize(preloaded.width) * usize(preloaded.height);
      if (out_buffer.len < num_pixels * 3) {
        return error.PcxLoadFailed;
      }
      var palette: [768]u8 = undefined;
      try loadIndexedWithStride(stream, preloaded, out_buffer, 3,
                                palette[0..]);
      var i: usize = 0;
      while (i < num_pixels) : (i += 1) {
        const index = usize(out_buffer[i*3+0]);
        out_buffer[i*3+0] = palette[index*3+0];
        out_buffer[i*3+1] = palette[index*3+1];
        out_buffer[i*3+2] = palette[index*3+2];
      }
    }

    pub fn loadRGBA(
      stream: *std.io.InStream(ReadError),
      preloaded: *const PreloadedInfo,
      transparent_index: ?u8,
      out_buffer: []u8,
    ) !void {
      const num_pixels = usize(preloaded.width) * usize(preloaded.height);
      if (out_buffer.len < num_pixels * 4) {
        return error.PcxLoadFailed;
      }
      var palette: [768]u8 = undefined;
      try loadIndexedWithStride(stream, preloaded, out_buffer, 4,
                                palette[0..]);
      var i: usize = 0;
      while (i < num_pixels) : (i += 1) {
        const index = usize(out_buffer[i*4+0]);
        out_buffer[i*4+0] = palette[index*3+0];
        out_buffer[i*4+1] = palette[index*3+1];
        out_buffer[i*4+2] = palette[index*3+2];
        out_buffer[i*4+3] =
          if ((transparent_index orelse ~index) == index) u8(0) else u8(255);
      }
    }
  };
}

pub fn Saver(comptime WriteError: type) type {
  return struct{
    const Self = this;

    pub fn saveIndexed(
      stream: *std.io.OutStream(WriteError),
      width: usize,
      height: usize,
      pixels: []const u8,
      palette: []const u8,
    ) !void {
      if (
        width < 1 or
        width > 65535 or
        height < 1 or
        height > 65535 or
        pixels.len < width * height or
        palette.len != 768
      ) {
        return error.PcxWriteFailed;
      }
      var i: usize = undefined;
      try stream.writeByte(0x0a); // manufacturer
      try stream.writeByte(5); // version
      try stream.writeByte(1); // encoding
      try stream.writeByte(8); // bits per pixel
      try stream.writeIntLe(u16, 0); // xmin
      try stream.writeIntLe(u16, 0); // ymin
      try stream.writeIntLe(u16, @intCast(u16, width - 1)); // xmax
      try stream.writeIntLe(u16, @intCast(u16, height - 1)); // ymax
      try stream.writeIntLe(u16, 0); // hres
      try stream.writeIntLe(u16, 0); // vres
      try stream.writeByteNTimes(0, 48); // 16-color palette
      try stream.writeByte(0); // reserved
      try stream.writeByte(1); // color planes
      try stream.writeIntLe(u16, @intCast(u16, width)); // bytes per line
      try stream.writeIntLe(u16, 1); // palette type
      try stream.writeByteNTimes(0, 58); // padding

      var y: usize = 0;
      while (y < height) : (y += 1) {
        const row = pixels[y * width..(y + 1) * width];
        var x: usize = 0;
        while (x < width) {
          const index = row[x];
          // look ahead to see how many subsequent pixels on the same row have
          // the same value
          var max = x + 63; // run cannot be longer than 63 pixels
          if (max > width) {
            max = width;
          }
          const old_x = x;
          while (x < max and row[x] == index) {
            x += 1;
          }
          // encode run
          const runlen = @intCast(u8, x - old_x);
          if (runlen > 1 or (index & 0xC0) == 0xC0) {
            try stream.writeByte(runlen | 0xC0);
          }
          try stream.writeByte(index);
        }
      }

      try stream.writeByte(0x0C);
      try stream.write(palette);
    }
  };
}
