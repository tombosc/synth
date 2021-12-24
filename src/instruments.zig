const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const G = @import("global_config.zig");
const print = std.debug.print;

const buf_size: u32 = 1000;
const zero_buf = [_]f32{0.0} ** buf_size;

pub const Instrument = struct {
    /// Interface for instruments.
    /// runtime polymorphism inspired by https://zig.news/david_vanderson/interfaces-in-zig-o1c
    /// playFn: compute soundwave of instrument
    ///     t0: offset in seconds.
    ///     n_frames: number of frames.
    ///     volume: in [0, 1]
    ///     returns buffer of audio
    // TODO change API so that we also pass a buffer, and we "add" to the buffer instead of assigning?
    // indeed some instruments like Sine do not need a buffer at all?
    playFn: fn (*Instrument, f32, u32, f32) []const f32,
    approx_start_time: f32,
    over: bool = false,

    pub fn play(instr: *Instrument, t0: f32, n_frames: u32, volume: f32) []const f32 {
        return (instr.playFn)(instr, t0, n_frames, volume);
    }
};

pub const Sine = struct {
    instrument: Instrument,
    buf: [buf_size]f32 = [_]f32{0.0} ** buf_size,
    duration: f32,
    freq: f32,

    pub fn play(instr: *Instrument, t0: f32, n_frames: u32, volume: f32) []const f32 {
        const self = @fieldParentPtr(Sine, "instrument", instr);
        if (instr.over) {
            return zero_buf[0..n_frames];
        }
        const rps = self.freq * 2.0 * std.math.pi;
        for (self.buf[0..n_frames]) |*v, i| {
            const fi = @intToFloat(f32, i);
            if ((t0 + G.sec_per_frame * fi) > self.duration) {
                instr.over = true;
                std.mem.set(f32, self.buf[i..n_frames], 0);
            }
            v.* = math.sin((t0 + fi * G.sec_per_frame) * rps) * volume;
        }
        return self.buf[0..n_frames];
    }
    pub fn init(approx_start_time: f32, duration: f32, freq: f32) @This() {
        return .{
            .instrument = Instrument{
                .approx_start_time = approx_start_time,
                .playFn = @This().play,
            },
            .duration = duration,
            .freq = freq,
        };
    }
};

test "sine" {
    var instr1 = Sine.init(0, 1, 440.0);
    print("Before play {}\n", .{instr1.buf[4]});
    const buf = instr1.instrument.play(0.1, 10, 1);
    print("After play {}\n", .{buf[4]});
}
