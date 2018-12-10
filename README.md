Loading and saving 8-bit PCX images in Zig. Works both at compile-time and at run-time (although performance at compile time is not great; this should be improved in future versions of Zig).

## Loading
Loading is split into two functions, both of which operate on a simple `InStream`.

The first function, `preload`, reads the PCX header and returns some basic information including its width and height. The caller is then expected to prepare and provide a byte slice of the appropriate size to the second function, `loadIndexed`/`loadRGB`/`loadRGBA`.

This separation allows the image library not to have to deal with allocators at all. The caller can provide heap-allocated memory, or simple a fixed-size static buffer (this is what makes the loader work at compile time).

`loadIndexed` returns the indexed image data (1 byte per pixel), and a 256-colour palette. `loadRGB` is a convenience function which loads the image then applies the palette and returns RGB image data (3 bytes per pixel). `loadRGBA` is similar but takes an optional transparent color index and returns RGBA (4 bytes per pixel).

Example:
```
var file = try std.os.File.openRead("image.pcx");
defer file.close();
var file_stream = std.os.File.inStream(file);
var stream = &file_stream.stream;
const Loader = pcx.Loader(std.os.File.InStream.Error);
const preloaded = try Loader.preload(stream);
const width = usize(preloaded.width);
const height = usize(preloaded.height);

// load indexed:
var pixels = try allocator.alloc(u8, width * height);
defer allocator.free(pixels);
var palette: [768]u8 = undefined;
try Loader.loadIndexed(stream, &preloaded, pixels, palette[0..]);

// load rgb:
var pixels = try allocator.alloc(u8, width * height * 3);
defer allocator.free(pixels);
try Loader.loadRGB(stream, &preloaded, pixels);

// load rgba:
var pixels = try allocator.alloc(u8, width * height * 4);
defer allocator.free(pixels);
const transparent = 255;
try Loader.loadRGBA(stream, &preloaded, transparent, pixels);
```

## Saving
Saving is simpler, you simply provide an `OutStream` and an image buffer and palette (only indexed colour is supported), and it will written to the stream.

Example:
```
const w = 32;
const h = 32;
const pixels: [32 * 32]u8 = ...;

var file = try std.os.File.openWrite("image.pcx");
defer file.close();
var file_stream = std.os.File.outStream(file);
var stream = &file_stream.stream;
const Saver = pcx.Saver(std.os.File.OutStream.Error);

try Saver.saveIndexed(stream, w, h, pixels[0..]);
```

## The code
The implementation is contained in `pcx.zig`, which is a standalone file (it only imports std).

The basic test suite can be run with `zig test test/pcx_test.zig`.

There are two additional toy "tests" which render an ASCII translation of an image. The comptime version writes it as a compile error, the runtime version prints it as usual.

```
zig test pcx_test_comptime.zig
zig test pcx_test_runtime.zig
```

### Credit
Space merc image from https://opengameart.org/content/space-merc
