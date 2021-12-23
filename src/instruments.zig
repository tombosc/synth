const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const G = @import("global_config.zig");
const print = std.debug.print;

/// Play a 440hz sine wave.
/// t0: offset in seconds.
/// n_frames: number of frames.
/// volume: in [0, 1]
pub fn play_sine(alloc: Allocator, t0: f32, n_frames: u32, volume: f32) ![]f32 {
    var buf = try alloc.alloc(f32, n_frames);
    const rps = 440.0 * 2.0 * std.math.pi;
    const seconds_per_frame: f32 = 1.0 / @intToFloat(f32, G.sample_rate);
    for (buf) |*v, i| {
        const fi = @intToFloat(f32, i);
        v.* = math.sin((t0 + fi * seconds_per_frame) * rps) * volume;
    }
    return buf;
}

test "sine" {
    var alloc = std.testing.allocator;
    print("Sine test\n", .{});
    const buf = try play_sine(alloc, 0, 10, 1);
    for (buf) |v|
        print("{} ", .{v});
    print("\n", .{});
    alloc.free(buf);
}
