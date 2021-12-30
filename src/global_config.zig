pub const sample_rate: u32 = 44100;
pub const verbose: u8 = 1;
pub const sec_per_frame: f32 = 1.0 / @intToFloat(f32, sample_rate);
pub const buf_size: u32 = 50000;
