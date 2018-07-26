const std = @import("std");

pub const PreloadedInfo = struct {
  width: u16,
  height: u16,
  bytes_per_line: u16,
};

pub fn preload(comptime ReadError: type, stream: *std.io.InStream(ReadError)) !PreloadedInfo {
  var header: [128]u8 = undefined;
  _ = try stream.readNoEof(header[0..]);
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
      xmax - xmin + 1 < 1 or
      xmax - xmin + 1 > 4096 or
      ymax - ymin + 1 < 1 or
      ymax - ymin + 1 > 4096 or
      color_planes != 1) {
    return error.PcxLoadFailed;
  }
  return PreloadedInfo{
    .width = xmax - xmin + 1,
    .height = ymax - ymin + 1,
    .bytes_per_line = bytes_per_line,
  };
}

pub fn loadIntoRGB(
  comptime ReadError: type,
  stream: *std.io.InStream(ReadError),
  preloaded: *const PreloadedInfo,
  out_buffer: []u8,
) !void {
  const width = preloaded.width;
  const height = preloaded.height;
  if (out_buffer.len < width * height * 3) {
    return error.PcxLoadFailed;
  }
  // use stride when outputting indices, so we can convert to RGB in place
  const stride = 3;
  const datasize = width * height * 3;

  // load image data (1 byte per pixel)
  var out: usize = 0;
  var runlen: u8 = undefined;
  var y: u16 = 0;
  while (y < height) : (y += 1) {
    var x: u16 = 0;
    while (x < preloaded.bytes_per_line) {
      var databyte = try stream.readByte();
      if ((databyte & 0xc0) == 0xc0) {
        runlen = databyte & 0x3f;
        databyte = try stream.readByte();
      } else {
        runlen = 1;
      }
      while (runlen > 0) {
        runlen -= 1;
        if (x < width) {
          if (out >= datasize) return error.PcxLoadFailed;
          out_buffer[out] = databyte; out += stride;
        }
        x += 1;
      }
    }
  }
  if (out != datasize) {
    return error.PcxLoadFailed;
  }

  // load palette... this occupies the last 768 bytes of the file. because
  // there is no seeking, use a buffering scheme to recover the palette once
  // we actually hit the end of the file
  var page_bufs: [2][768]u8 = undefined;
  var pages: [2][]u8 = undefined;
  var which_page: u8 = 0;
  while (true) {
    const n = try stream.read(page_bufs[which_page][0..]);
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
  // the palette will either be completely contained in the current page; or
  // else its first part will be in the opposite page, and the rest in the
  // current page
  var palette = page_bufs[which_page];
  const cur_page = pages[which_page];
  const opp_page = pages[which_page ^ 1];
  const cur_len = cur_page.len;
  const opp_len = 768 - cur_len;
  std.mem.copyBackwards(u8, palette[opp_len..768], cur_page);
  std.mem.copy(u8, palette[0..opp_len], opp_page[cur_len..768]);

  // convert in place to true colour
  var i: usize = 0;
  while (i < width * height) : (i += 1) {
    const index = out_buffer[i*3+0];
    out_buffer[i*3+0] = palette[index*3+0];
    out_buffer[i*3+1] = palette[index*3+1];
    out_buffer[i*3+2] = palette[index*3+2];
  }
}
