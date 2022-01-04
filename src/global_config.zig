const std = @import("std");
const print = std.debug.print;

pub const sample_rate: u32 = 44100;
pub const verbose: u8 = 3;
pub const sec_per_frame: f32 = 1.0 / @intToFloat(f32, sample_rate);
pub const buf_size: u32 = 50000;

pub var start_timestamp: i128 = 0;

pub fn nowSeconds() f32 {
    return @intToFloat(f32, std.time.nanoTimestamp() - start_timestamp) / 1e9;
}
