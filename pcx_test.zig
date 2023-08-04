// some basic tests, just to make sure well formed images are handled

const std = @import("std");
const pcx = @import("pcx.zig");

var mem: [1000 * 1024]u8 = undefined;
var gfa = std.heap.FixedBufferAllocator.init(&mem);

fn testLoadComptime(
    comptime branch_quota: comptime_int,
    comptime basename: []const u8,
    comptime indexed: bool,
) void {
    comptime {
        @setEvalBranchQuota(branch_quota);

        const pcxfile = @embedFile("testdata/" ++ basename ++ ".pcx");
        var fbs = std.io.fixedBufferStream(pcxfile);
        var reader = fbs.reader();

        const preloaded = try pcx.preload(reader);
        const width: usize = preloaded.width;
        const height: usize = preloaded.height;

        if (indexed) {
            var pixels: [width * height]u8 = undefined;
            var palette: [768]u8 = undefined;
            try pcx.loadIndexed(reader, preloaded, &pixels, &palette);

            try std.testing.expect(std.mem.eql(
                u8,
                &pixels,
                @embedFile("testdata/" ++ basename ++ "-raw-indexed.data"),
            ));
            try std.testing.expect(std.mem.eql(
                u8,
                &palette,
                @embedFile("testdata/" ++ basename ++ "-raw-indexed.data.pal"),
            ));
        } else {
            var pixels: [width * height * 3]u8 = undefined;
            try pcx.loadRGB(reader, preloaded, &pixels);

            try std.testing.expect(std.mem.eql(
                u8,
                &pixels,
                @embedFile("testdata/" ++ basename ++ "-raw-r8g8b8.data"),
            ));
        }
    }
}

fn testLoadRuntime(comptime basename: []const u8, indexed: bool) !void {
    defer gfa.end_index = 0;

    const pcxfile = @embedFile("testdata/" ++ basename ++ ".pcx");
    var fbs = std.io.fixedBufferStream(pcxfile);
    const reader = fbs.reader();

    const preloaded = try pcx.preload(reader);
    const width: usize = preloaded.width;
    const height: usize = preloaded.height;

    if (indexed) {
        var pixels = try gfa.allocator().alloc(u8, width * height);
        var palette: [768]u8 = undefined;
        try pcx.loadIndexed(reader, preloaded, pixels, &palette);

        try std.testing.expect(std.mem.eql(
            u8,
            pixels,
            @embedFile("testdata/" ++ basename ++ "-raw-indexed.data"),
        ));
        try std.testing.expect(std.mem.eql(
            u8,
            &palette,
            @embedFile("testdata/" ++ basename ++ "-raw-indexed.data.pal"),
        ));
    } else {
        var rgb = try gfa.allocator().alloc(u8, width * height * 3);
        try pcx.loadRGB(reader, preloaded, rgb);

        try std.testing.expect(std.mem.eql(
            u8,
            rgb,
            @embedFile("testdata/" ++ basename ++ "-raw-r8g8b8.data"),
        ));
    }
}

test "load space_merc.pcx indexed comptime" {
    testLoadComptime(20000, "space_merc", true);
}

test "load space_merc.pcx rgb comptime" {
    testLoadComptime(20000, "space_merc", false);
}

test "load space_merc.pcx indexed runtime" {
    try testLoadRuntime("space_merc", true);
}

test "load space_merc.pcx rgb runtime" {
    try testLoadRuntime("space_merc", false);
}

// comptime loading is slow so skip these tests

test "load lena64.pcx indexed comptime" {
    if (true) return error.SkipZigTest;
    testLoadComptime(100000, "lena64", true);
}

test "load lena128.pcx indexed comptime" {
    if (true) return error.SkipZigTest;
    testLoadComptime(200000, "lena128", true);
}

test "load lena256.pcx indexed comptime" {
    if (true) return error.SkipZigTest;
    testLoadComptime(500000, "lena256", true);
}

// this one crashes after 20 seconds with the message "fork failed"
test "load lena512.pcx indexed comptime" {
    if (true) return error.SkipZigTest;
    testLoadComptime(20000000, "lena512", true);
}

test "load lena512.pcx indexed runtime" {
    try testLoadRuntime("lena512", true);
}

test "load lena512.pcx rgb runtime" {
    try testLoadRuntime("lena512", false);
}

// note: these resized lena images are not very useful for testing the loader
// (especially since they have even dimensions and as photos they are not
// suited for RLE), but they are useful for benchmarking, which i want to do
// eventually

test "load lena256.pcx indexed runtime" {
    try testLoadRuntime("lena256", true);
}

test "load lena256.pcx rgb runtime" {
    try testLoadRuntime("lena256", false);
}

test "load lena128.pcx indexed runtime" {
    try testLoadRuntime("lena128", true);
}

test "load lena128.pcx rgb runtime" {
    try testLoadRuntime("lena128", false);
}

test "load lena64.pcx indexed runtime" {
    try testLoadRuntime("lena64", true);
}

test "load lena64.pcx rgb runtime" {
    try testLoadRuntime("lena64", false);
}

fn testSave(comptime basename: []const u8, w: usize, h: usize) !void {
    const pcxfile = @embedFile("testdata/" ++ basename ++ ".pcx");

    var outbuf: [pcxfile.len]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&outbuf);

    try pcx.saveIndexed(
        fbs.writer(),
        w,
        h,
        @embedFile("testdata/" ++ basename ++ "-raw-indexed.data"),
        @embedFile("testdata/" ++ basename ++ "-raw-indexed.data.pal"),
    );

    const result = fbs.getWritten();

    try std.testing.expect(
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
        try testSave("space_merc", 32, 32);
    }
}

test "save lena64.pcx comptime" {
    if (true) return error.SkipZigTest;
    comptime {
        @setEvalBranchQuota(100000);
        try testSave("lena64", 64, 64);
    }
}

test "save lena128.pcx comptime" {
    if (true) return error.SkipZigTest;
    comptime {
        @setEvalBranchQuota(500000);
        try testSave("lena128", 128, 128);
    }
}

// this one crashes with "fork failed"
test "save lena256.pcx comptime" {
    if (true) return error.SkipZigTest;
    comptime {
        @setEvalBranchQuota(2000000);
        try testSave("lena256", 256, 256);
    }
}

// haven't even tried this one
test "save lena512.pcx comptime" {
    if (true) return error.SkipZigTest;
    comptime {
        @setEvalBranchQuota(10000000);
        try testSave("lena512", 512, 512);
    }
}

test "save space_merc.pcx runtime" {
    try testSave("space_merc", 32, 32);
}

test "save lena64.pcx runtime" {
    try testSave("lena64", 64, 64);
}

test "save lena128.pcx runtime" {
    try testSave("lena128", 128, 128);
}

test "save lena256.pcx runtime" {
    try testSave("lena256", 256, 256);
}

test "save lena512.pcx runtime" {
    try testSave("lena512", 512, 512);
}
