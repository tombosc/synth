const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const G = @import("global_config.zig");
const print = std.debug.print;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectError = std.testing.expectError;

const buf_size: u32 = 100000;
const zero_buf = [_]f32{0.0} ** buf_size;

pub const Instrument = struct {
    /// Interface for instruments.
    /// runtime polymorphism inspired by https://zig.news/david_vanderson/interfaces-in-zig-o1c
    /// playFn: compute soundwave of instrument
    ///     t0: offset in seconds.
    ///     n_frames: number of frames.
    ///     returns buffer of audio
    // TODO change API so that we also pass a buffer, and we "add" to the buffer instead of assigning?
    // indeed some instruments like Sine do not need a buffer at all?
    playFn: fn (*Instrument, f32, u32) []const f32,
    deinitFn: fn (*Instrument, Allocator) void,
    approx_start_time: f32,
    volume: f32,
    over: bool = false,

    pub fn play(instr: *Instrument, t0: f32, n_frames: u32) []const f32 {
        // print("PL {*}\n", .{instr});
        return (instr.playFn)(instr, t0, n_frames);
    }
    pub fn deinit(instr: *Instrument, alloc: Allocator) void {
        return (instr.deinitFn)(instr, alloc);
    }
};

pub const Signal = union(enum) {
    instrument: *Instrument,
    constant: f32,
};

const tuple_types = [_]type{ @TypeOf(.{f32}), @TypeOf(.{ f32, f32 }), @TypeOf(.{ f32, f32, f32 }) };

// one way to create an instrument and compose them easily. See createKick for example.
/// * f: a function with signature: fn(f32, ...), where
///   - f32 is t0
///   - the rest of the arguments are other values
/// * L: the number of other arguments (except t0)
pub fn FF(comptime f: anytype, comptime L: u32) type {
    // L can be deduced from f, but this way the user explicitely writes the
    // number of arguments to pass.
    // TODO instead of a simple function of a single f32 time that returns a single f32,
    // take a whole []f32 and return []f32?
    // benefits: 1) faster and 2) allows for filters?
    const PlainFnArgsType = comptime std.meta.ArgsTuple(@TypeOf(f));
    // TODO no comptime checks because I can't have "try FF..." outside of a function?
    // old comptime checks
    // const L = comptime in_instr.len;
    // const args_tmp: PlainFnArgsType = undefined;
    // args only used in the following check:
    // if ((args_tmp.len - 1) != L) {
    //     return error.WrongArgNumber;
    // }
    const PlayFnArgsType = std.meta.ArgsTuple(@TypeOf(Instrument.play));

    return struct {
        instrument: Instrument,
        inputs: [L]Signal,
        buf: []f32,

        pub fn play(instr: *Instrument, t0: f32, n_frames: u32) []const f32 {
            var self = @fieldParentPtr(@This(), "instrument", instr);
            // print("call play() with instr={*}, L={}, LL={}\n", .{ instr, L, self.LL });
            if (instr.over) {
                return zero_buf[0..n_frames];
            }

            var args: PlainFnArgsType = undefined;
            var i: u32 = 0;
            var res_bufs = [_]?[]const f32{undefined} ** (L);
            while (i < L) : (i += 1) {
                // const PlayFnArgsType = std.meta.ArgsTuple(@TypeOf(@This().play));
                var sub_args: PlayFnArgsType = undefined;
                switch (self.inputs[i]) {
                    .instrument => {
                        sub_args[0] = self.inputs[i].instrument;
                        sub_args[1] = t0;
                        sub_args[2] = n_frames;
                        // print("L={}, instr={*}, sub_args={}\n", .{ L, instr, sub_args });
                        res_bufs[i] = @call(.{}, self.inputs[i].instrument.playFn, sub_args);
                    },
                    .constant => {},
                }
            }
            for (self.buf[0..n_frames]) |*v, t| {
                const ft = @intToFloat(f32, t);
                // print("wrap L {}, args {}, {}\n", .{ L, args, @field(args, "0") });
                args[0] = t0 + ft * G.sec_per_frame;
                // TODO doing this with a while loop and comptime var k doesn't work...
                if (L >= 1) {
                    switch (self.inputs[0]) {
                        .instrument => {
                            args[1] = res_bufs[0].?[t];
                        },
                        .constant => {
                            args[1] = self.inputs[0].constant;
                        },
                    }
                }
                if (L >= 2) {
                    switch (self.inputs[1]) {
                        .instrument => {
                            args[2] = res_bufs[1].?[t];
                        },
                        .constant => {
                            args[2] = self.inputs[1].constant;
                        },
                    }
                }
                if (L >= 3) {
                    switch (self.inputs[2]) {
                        .instrument => {
                            args[3] = res_bufs[2].?[t];
                        },
                        .constant => {
                            args[3] = self.inputs[2].constant;
                        },
                    }
                }
                // print("after args {}\n", .{args});
                v.* = @call(.{}, f, args);
            }
            // print("Return L{}\n", .{L});
            return self.buf[0..n_frames];
        }

        pub fn init(alloc: Allocator, approx_start_time: f32, duration: f32, volume: f32, instruments: [L]Signal) !*@This() {
            const S = @This();
            // TODO duration? or should duration be handled inside the function directly?
            _ = duration;
            _ = approx_start_time;
            _ = instruments;
            var buf = try alloc.alloc(f32, buf_size);
            if (L != instruments.len) {
                print(
                    "Error! Not enough Signals. Expected {}, got {}.\n",
                    .{ instruments.len, L },
                );
                return error.WrongArgNumber;
            }
            var a = try alloc.create(S);
            a.* = @This(){
                .instrument = Instrument{
                    .approx_start_time = approx_start_time,
                    .playFn = @This().play,
                    .deinitFn = @This().deinit,
                    .volume = volume,
                },
                .inputs = instruments,
                .buf = buf,
            };
            return a;
        }

        pub fn deinit(instr: *Instrument, alloc: Allocator) void {
            var self = @fieldParentPtr(@This(), "instrument", instr);
            for (self.inputs) |i| {
                switch (i) {
                    .constant => {},
                    .instrument => {
                        i.instrument.deinit(alloc);
                    },
                }
            }
            alloc.free(self.buf);
            alloc.destroy(self);
        }
    };
}

// pub fn kickFreq(t: f32, f: f32) f32 {
pub fn kickFreq(t: f32, f: f32, v: f32) f32 {
    return f / std.math.pow(f32, (t + 0.001), v);
}
pub fn osc(t: f32, f: f32) f32 {
    return std.math.sin(t * std.math.pi * f);
}

const Osc = FF(osc, 1);

pub fn createOsc(alloc: Allocator, t0: f32, vol: f32, f: f32) !*Instrument {
    var vf: f32 = f;
    var ins = [_]Signal{.{ .constant = vf * t0 }};
    var osc_ = try FF(osc, 1).init(alloc, t0, 0.0, vol, ins);
    // print("Here, init osc {*}\n", .{osc_.instrument});
    return &osc_.instrument;
}

pub fn createKick(alloc: Allocator, t0: f32, vol: f32, f: f32, v: f32) !*Instrument {
    var ins = [_]Signal{
        .{ .constant = f },
        .{ .constant = v },
    };
    var kick_freq = try FF(kickFreq, 2).init(alloc, t0, 0.0, 1.0, ins);

    var kick = try FF(osc, 1).init(alloc, t0, 0.0, vol, [1]Signal{.{ .instrument = &kick_freq.instrument }});
    // print("Here, init kick {*}\n", .{kick.instrument});
    return &kick.instrument;
}

test "kick" {
    var alloc = std.testing.allocator;
    var kick_i = try createKick(alloc, 0.3, 0.3, 100, 0.45);
    defer kick_i.deinit(alloc);
    const buf = kick_i.play(0, 100);
    _ = buf;
}
