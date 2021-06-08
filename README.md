# zig-pcx

One-file library ([pcx.zig](pcx.zig)) for loading and saving 8-bit PCX images
in Zig; works both at compile-time and at run-time.

Requires Zig 0.8.0.

## Loading

PCX images can be loaded from any `Reader`. The loading API has two stages:
"preload" and "load".

First, you call `preload`. This reads the PCX header and returns some basic
information including its width and height (and some other things which are
used internally).

Preload function:

```zig
preload(reader: *Reader) !PreloadedInfo
```

Then, if you want to proceed with decoding the image, you call one of the
`load*` functions. You pass it the value returned by `preload`, as well as a
byte slice with enough space to fit the decompressed image. (The caller is
responsible for allocating this.)

Load functions:

```zig
// loads the color index values into `out_buffer` without doing palette lookup.
// if `out_palette` is supplied, loads the palette in RGB format.
// `out_buffer` size should be `width * height` bytes.
// `out_palette` size should be 768 bytes (256 colors of 3 bytes each).
loadIndexed(reader: *Reader, preloaded: PreloadedInfo, out_buffer: []u8, out_palette: ?[]u8) !void

// uses palette internally to resolve pixel colors.
// `out_buffer` size should be `width * height * 3` bytes.
loadRGB(reader: *Reader, preloaded: PreloadedInfo, out_buffer: []u8) !void

// reads into an RGBA buffer. if you pass a `transparent_index`, pixels with
// that value will given a 0 alpha value instead of 255.
// `out_buffer` size should be `width * height * 4` bytes.
loadRGBA(reader: *Reader, preloaded: PreloadedInfo, transparent_index: ?u8, out_buffer: []u8) !void
```

Note: the PCX format stores width and height as 16-bit integers. So be sure
to upcast them to `usize` before multiplying them together, otherwise you'll
get an overflow with images bigger than ~256x256.

Example usage:

```zig
var file = try std.fs.cwd().openFile("image.pcx", .{});
defer file.close();
var reader = file.reader();
const Loader = pcx.Loader(@TypeOf(reader));
const preloaded = try Loader.preload(&reader);
const width: usize = preloaded.width;
const height: usize = preloaded.height;

// load indexed:
var pixels = try allocator.alloc(u8, width * height);
defer allocator.free(pixels);
var palette: [768]u8 = undefined;
try Loader.loadIndexed(&reader, preloaded, pixels, &palette);

// or, load rgb:
var pixels = try allocator.alloc(u8, width * height * 3);
defer allocator.free(pixels);
try Loader.loadRGB(&reader, preloaded, pixels);

// or, load rgba:
var pixels = try allocator.alloc(u8, width * height * 4);
defer allocator.free(pixels);
const transparent: ?u8 = 255;
try Loader.loadRGBA(&reader, preloaded, transparent, pixels);
```

Compile-time example:

```zig
comptime {
    @setEvalBranchQuota(100000);

    const input = @embedFile("image.pcx");
    var fbs = std.io.fixedBufferStream(input);
    var reader = fbs.reader();
    const Loader = pcx.Loader(@TypeOf(reader));
    const preloaded = try Loader.preload(&reader);
    const width: usize = preloaded.width;
    const height: usize = preloaded.height;

    // no need to use allocators at compile-time
    var rgb: [width * height * 3]u8 = undefined;
    try Loader.loadRGB(&reader, preloaded, &rgb);
}
```

## Saving

Saving is simpler: you simply provide an `Writer` and an image buffer and
palette (only indexed color is supported), and it will be written to the
stream.

Example:

```zig
const w = 32;
const h = 32;
const pixels: [32 * 32]u8 = ...;
const palette: [768]u8 = ...;

var file = try std.fs.cwd().createFile("image.pcx", .{});
defer file.close();
var writer = file.writer();
const Saver = pcx.saver(&writer);

try saver.saveIndexed(w, h, &pixels, &palette);
```

## Tests and demos

The basic test suite can be run with `zig test test.zig`.

There are two additional "demo" programs which render an ASCII translation of
a stock image. The comptime version renders it in the form of a compile
error, the runtime version prints it to stderr.

```
zig run demo_comptime.zig
zig run demo_runtime.zig
```

### Credit

Space merc image (used in demos) from https://opengameart.org/content/space-merc
