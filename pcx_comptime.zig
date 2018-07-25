const std = @import("std");

const DecompressedPcxImage = struct {
  width: u16,
  height: u16,
  data: []const u8, // 3 bytes per pixel
};

fn decompress_pcx(comptime filedata: []const u8) !DecompressedPcxImage {
  if (filedata.len < 128+768) {
    return error.Failed;
  }
  const manufacturer = filedata[0];
  const version = filedata[1];
  if (manufacturer != 0x0a or version != 5) {
    return error.Failed;
  }
  const encoding = filedata[2];
  const bits_per_pixel = filedata[3];
  const xmin = u16(filedata[4]) | (u16(filedata[5]) << 8);
  const ymin = u16(filedata[6]) | (u16(filedata[7]) << 8);
  const xmax = u16(filedata[8]) | (u16(filedata[9]) << 8);
  const ymax = u16(filedata[10]) | (u16(filedata[11]) << 8);
  const hres = u16(filedata[12]) | (u16(filedata[13]) << 8);
  const vres = u16(filedata[14]) | (u16(filedata[15]) << 8);
  const reserved = filedata[64];
  const color_planes = filedata[65];
  const bytes_per_line = u16(filedata[66]) | (u16(filedata[67]) << 8);
  const palette_type = u16(filedata[68]) | (u16(filedata[69]) << 8);
  if (encoding != 1 or
      bits_per_pixel != 8 or
      xmax - xmin + 1 < 1 or
      xmax - xmin + 1 > 4096 or
      ymax - ymin + 1 < 1 or
      ymax - ymin + 1 > 4096 or
      color_planes != 1) {
    return error.Failed;
  }
  const width = xmax - xmin + 1;
  const height = ymax - ymin + 1;
  const datasize = width * height;
  var indices: [width * height]u8 = undefined;

  // load image data (1 byte per pixel)
  var in: usize = 128;
  var out: usize = 0;
  var runlen: u8 = undefined;
  var y: u16 = 0;
  while (y < height) : (y += 1) {
    var x: u16 = 0;
    while (x < bytes_per_line) {
      if (in >= filedata.len - 768) return error.Failed;
      var databyte = filedata[in]; in += 1;
      if ((databyte & 0xc0) == 0xc0) {
        runlen = databyte & 0x3f;
        if (in >= filedata.len - 768) return error.Failed;
        databyte = filedata[in]; in += 1;
      } else {
        runlen = 1;
      }
      while (runlen > 0) {
        runlen -= 1;
        if (x < width) {
          if (out >= datasize) return error.Failed;
          indices[out] = databyte; out += 1;
        }
        x += 1;
      }
    }
  }

  // load palette
  const palette = filedata[filedata.len - 768..filedata.len];

  // convert to true colour
  var data: [width * height * 3]u8 = undefined;
  var i: usize = 0;
  while (i < width * height) : (i += 1) {
    const index = indices[i];
    data[i*3+0] = palette[index*3+0];
    data[i*3+1] = palette[index*3+1];
    data[i*3+2] = palette[index*3+2];
  }

  return DecompressedPcxImage{
    .width = width,
    .height = height,
    .data = data,
  };
}

fn convertToGreyscale(comptime pixels: []const u8) []const u8 {
  const num_pixels = @divExact(pixels.len, 3);
  var output: [num_pixels]u8 = undefined;
  var i: usize = 0;
  while (i < num_pixels) : (i += 1) {
    const r = @intToFloat(f32, pixels[i*3+0]) / 255.0;
    const g = @intToFloat(f32, pixels[i*3+1]) / 255.0;
    const b = @intToFloat(f32, pixels[i*3+2]) / 255.0;
    const grey = 0.21 * r + 0.72 * g + 0.07 * b;
    output[i] = @floatToInt(u8, grey * 255);
  }
  return output;
}

const grey10 = " .:-=+*#%@"; // http://paulbourke.net/dataformats/asciiart/

test "" {
  comptime {
    @setEvalBranchQuota(10000);
    const input = @embedFile("space_merc.pcx");
    const result = try decompress_pcx(input);
    const greyscale = convertToGreyscale(result.data);
    var string: [(result.width+1)*result.height]u8 = undefined;
    var i: usize = 0;
    var y: usize = 0;
    while (y < result.height) : (y += 1) {
      string[i] = '\n'; i += 1;
      var x: usize = 0;
      while (x < result.width) : (x += 1) {
        const shade256 = greyscale[y*result.width+x];
        const quant = @divFloor(shade256, 26);
        string[i] = grey10[9 - quant]; i += 1;
      }
    }
    @compileLog(string);
  }
}
