const std = @import("std");

pub const PreloadedInfo = struct {
    width: u16,
    height: u16,
    bytes_per_line: u16,
};

pub fn preload(reader: anytype) !PreloadedInfo {
    var header: [70]u8 = undefined;
    _ = try reader.readNoEof(&header);
    try reader.skipBytes(58, .{});
    const manufacturer = header[0];
    const version = header[1];
    if (manufacturer != 0x0a or version != 5) {
        return error.PcxLoadFailed;
    }
    const encoding = header[2];
    const bits_per_pixel = header[3];
    const xmin = @as(u16, header[4]) | (@as(u16, header[5]) << 8);
    const ymin = @as(u16, header[6]) | (@as(u16, header[7]) << 8);
    const xmax = @as(u16, header[8]) | (@as(u16, header[9]) << 8);
    const ymax = @as(u16, header[10]) | (@as(u16, header[11]) << 8);
    // const hres = @as(u16, header[12]) | (@as(u16, header[13]) << 8);
    // const vres = @as(u16, header[14]) | (@as(u16, header[15]) << 8);
    // const reserved = header[64];
    const color_planes = header[65];
    const bytes_per_line = @as(u16, header[66]) | (@as(u16, header[67]) << 8);
    // const palette_type = @as(u16, header[68]) | (@as(u16, header[69]) << 8);
    if (encoding != 1 or
        bits_per_pixel != 8 or
        xmin > xmax or
        ymin > ymax or
        color_planes != 1)
    {
        return error.PcxLoadFailed;
    }
    return PreloadedInfo{
        .width = xmax - xmin + 1,
        .height = ymax - ymin + 1,
        .bytes_per_line = bytes_per_line,
    };
}

pub fn loadIndexed(
    reader: anytype,
    preloaded: PreloadedInfo,
    out_buffer: []u8,
    out_palette: ?[]u8,
) !void {
    try loadIndexedWithStride(reader, preloaded, out_buffer, 1, out_palette);
}

// this function is mostly useful as a helper to loadRGB and loadRGBA, which
// use it in order to avoid having to allocate two buffers (one for indexed
// and one for true color).
pub fn loadIndexedWithStride(
    reader: anytype,
    preloaded: PreloadedInfo,
    out_buffer: []u8,
    out_buffer_stride: usize,
    out_palette: ?[]u8,
) !void {
    var input_buffer: [128]u8 = undefined;
    var input: []u8 = input_buffer[0..0];

    if (out_buffer_stride < 1) {
        return error.PcxLoadFailed;
    }
    if (out_palette) |pal| {
        if (pal.len < 768) {
            return error.PcxLoadFailed;
        }
    }
    const width: usize = preloaded.width;
    const height: usize = preloaded.height;
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
                    const n = try reader.read(&input_buffer);
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
                        const n = try reader.read(&input_buffer);
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

    // load palette... this occupies the last 768 bytes of the file. as there
    // is no seeking, use a buffering scheme to recover the palette once we
    // actually hit the end of the file.
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
        n += try reader.read(page_bufs[which_page][n..]);
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
    if (out_palette) |pal| {
        std.mem.copy(u8, pal[0..opp_len], opp_page[cur_len..768]);
        std.mem.copy(u8, pal[opp_len..768], cur_page);
    }
}

pub fn loadRGB(
    reader: anytype,
    preloaded: PreloadedInfo,
    out_buffer: []u8,
) !void {
    const num_pixels = @as(usize, preloaded.width) * @as(usize, preloaded.height);
    if (out_buffer.len < num_pixels * 3) {
        return error.PcxLoadFailed;
    }
    var palette: [768]u8 = undefined;
    try loadIndexedWithStride(reader, preloaded, out_buffer, 3, &palette);
    var i: usize = 0;
    while (i < num_pixels) : (i += 1) {
        const index: usize = out_buffer[i * 3 + 0];
        out_buffer[i * 3 + 0] = palette[index * 3 + 0];
        out_buffer[i * 3 + 1] = palette[index * 3 + 1];
        out_buffer[i * 3 + 2] = palette[index * 3 + 2];
    }
}

pub fn loadRGBA(
    reader: anytype,
    preloaded: PreloadedInfo,
    transparent_index: ?u8,
    out_buffer: []u8,
) !void {
    const num_pixels = @as(usize, preloaded.width) * @as(usize, preloaded.height);
    if (out_buffer.len < num_pixels * 4) {
        return error.PcxLoadFailed;
    }
    var palette: [768]u8 = undefined;
    try loadIndexedWithStride(reader, preloaded, out_buffer, 4, &palette);
    var i: usize = 0;
    while (i < num_pixels) : (i += 1) {
        const index: usize = out_buffer[i * 4 + 0];
        out_buffer[i * 4 + 0] = palette[index * 3 + 0];
        out_buffer[i * 4 + 1] = palette[index * 3 + 1];
        out_buffer[i * 4 + 2] = palette[index * 3 + 2];
        out_buffer[i * 4 + 3] =
            if ((transparent_index orelse ~index) == index) 0 else 255;
    }
}

pub fn saveIndexed(
    writer: anytype,
    width: usize,
    height: usize,
    pixels: []const u8,
    palette: []const u8,
) !void {
    if (width < 1 or
        width > 65535 or
        height < 1 or
        height > 65535 or
        pixels.len < width * height or
        palette.len != 768)
    {
        return error.PcxWriteFailed;
    }
    const xmax: u16 = @intCast(width - 1);
    const ymax: u16 = @intCast(height - 1);
    const bytes_per_line: u16 = @intCast(width);
    const palette_type: u16 = 1;
    var header: [128]u8 = undefined;
    header[0] = 0x0a; // manufacturer
    header[1] = 5; // version
    header[2] = 1; // encoding
    header[3] = 8; // bits per pixel
    header[4] = 0;
    header[5] = 0; // xmin
    header[6] = 0;
    header[7] = 0; // ymin
    header[8] = @intCast(xmax & 0xff);
    header[9] = @intCast(xmax >> 8);
    header[10] = @intCast(ymax & 0xff);
    header[11] = @intCast(ymax >> 8);
    header[12] = 0;
    header[13] = 0; // hres
    header[14] = 0;
    header[15] = 0; // vres
    @memset(header[16..64], 0);
    header[64] = 0; // reserved
    header[65] = 1; // color planes
    header[66] = @intCast(bytes_per_line & 0xff);
    header[67] = @intCast(bytes_per_line >> 8);
    header[68] = @intCast(palette_type & 0xff);
    header[69] = @intCast(palette_type >> 8);
    @memset(header[70..128], 0);
    try writer.writeAll(&header);

    var y: usize = 0;
    while (y < height) : (y += 1) {
        const row = pixels[y * width .. (y + 1) * width];
        var x: usize = 0;
        while (x < width) {
            const index = row[x];
            // look ahead to see how many subsequent pixels on the same
            // row have the same value
            var max = x + 63; // run cannot be longer than 63 pixels
            if (max > width) {
                max = width;
            }
            const old_x = x;
            while (x < max and row[x] == index) {
                x += 1;
            }
            // encode run
            const runlen: u8 = @intCast(x - old_x);
            if (runlen > 1 or (index & 0xc0) == 0xc0) {
                try writer.writeByte(runlen | 0xc0);
            }
            try writer.writeByte(index);
        }
    }

    try writer.writeByte(0x0c);
    try writer.writeAll(palette);
}
