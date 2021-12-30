const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const G = @import("global_config.zig");
const print = std.debug.print;
const panic = std.debug.panic;
const expect = std.testing.expect;
const expectError = std.testing.expectError;

const buf_size: u32 = G.buf_size;
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

// one way to create an instrument and compose them easily. See createKick for example.
/// * f: a function with signature: fn(f32, ...), where
///   - f32 is t0
///   - the rest of the arguments are other values
/// * L: the number of other arguments (except t0)
/// * InputTypes: either f32 for float constant, or the FF generated type (not Instrument, despite the name)
pub fn FF(comptime f: anytype, comptime InputTypes: anytype, comptime EnvelopeType: ?type) type {
    // TODO instead of a simple function of a single f32 time that returns a single f32,
    // take a whole []f32 and return []f32?
    // benefits: 1) faster and 2) allows for filters?
    const PlainFnArgsType = comptime std.meta.ArgsTuple(@TypeOf(f));
    const L = comptime InputTypes.len;
    // TODO reinstate this check?
    // const args_tmp: PlainFnArgsType = undefined;
    // args only used in the following check:
    // if ((args_tmp.len - 1) != L) {
    //     return error.WrongArgNumber;
    // }
    const PlayFnArgsType = std.meta.ArgsTuple(@TypeOf(Instrument.play));

    return struct {
        instrument: Instrument,
        inputs: [L]Signal,
        envelope: ?Signal,
        buf: []f32,

        pub fn play(instr: *Instrument, t0: f32, n_frames: u32) []const f32 {
            // @setRuntimeSafety(true);
            var self = @fieldParentPtr(@This(), "instrument", instr);

            // print("call play() with instr={*}, L={}, LL={}\n", .{ instr, L, self.LL });
            if (instr.over) {
                return zero_buf[0..n_frames];
            }

            var args: PlainFnArgsType = undefined;

            var res_bufs = [_]?[]const f32{undefined} ** (L);
            inline for (InputTypes) |IType, i| {
                switch (IType) {
                    f32 => {
                        args[i + 1] = self.inputs[i].constant;
                    },
                    else => {
                        var sub_args: PlayFnArgsType = undefined;
                        sub_args[0] = self.inputs[i].instrument;
                        sub_args[1] = t0;
                        sub_args[2] = n_frames;
                        // print("L={}, instr={*}, sub_args={}\n", .{ L, instr, sub_args });
                        // dynamic dispatch was
                        // res_bufs[i] = @call(.{}, self.inputs[i].instrument.playFn, sub_args);
                        // static dispatch:
                        res_bufs[i] = @call(.{}, IType.play, sub_args);
                        // print("subcall {}\n", .{res_bufs[i].?[5]});
                    },
                }
            }
            var env_buf: ?[]const f32 = null;
            var env_val: ?f32 = null;
            if (EnvelopeType) |T| {
                switch (T) {
                    f32 => env_val = self.envelope.?.constant,
                    else => {
                        var sub_args: PlayFnArgsType = undefined;
                        sub_args[0] = self.envelope.?.instrument;
                        sub_args[1] = t0;
                        sub_args[2] = n_frames;
                        env_buf = @call(.{}, T.play, sub_args);
                    },
                }
            }
            for (self.buf[0..n_frames]) |*v, t| {
                const ft = @intToFloat(f32, t);
                // print("wrap L {}, args {}, {}\n", .{ L, args, @field(args, "0") });
                args[0] = t0 + (ft * G.sec_per_frame);
                inline for (InputTypes) |IType, i| {
                    switch (IType) {
                        f32 => {},
                        else => {
                            args[i + 1] = res_bufs[i].?[t];
                        },
                    }
                }
                var result = @call(.{}, f, args);
                if (env_val) |env_val_| {
                    v.* = result * env_val_;
                } else if (env_buf) |env_buf_| {
                    v.* = result * env_buf_[t];
                } else {
                    v.* = result;
                }
            }
            // print("Return L{}\n", .{L});
            return self.buf[0..n_frames];
        }

        pub fn init(alloc: Allocator, approx_start_time: f32, duration: f32, volume: f32, instruments: [L]Signal, envelope: ?Signal) !*@This() {
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
                .envelope = envelope,
                .buf = buf,
            };
            print("Init instr {*}\n", .{&a.instrument});
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
    // @setRuntimeSafety(true);
    return f / std.math.pow(f32, (t + 0.001), v);
}
pub fn osc(t: f32, f: f32) f32 {
    // @setRuntimeSafety(true);
    return std.math.sin(t * std.math.pi * f);
}

pub fn linearEnv(t: f32, slope: f32) f32 {
    return math.max(1 + slope * t, 0);
}

pub fn createOsc(alloc: Allocator, t0: f32, vol: f32, f: f32, slope: f32) !*Instrument {
    const Env = FF(linearEnv, .{f32}, null);
    var linear_env = try Env.init(alloc, t0, 0.0, 1.0, [1]Signal{.{ .constant = slope }}, null);
    const Osc = FF(osc, .{f32}, Env);
    var ins = [_]Signal{.{ .constant = f }};
    var osc_ = try Osc.init(alloc, t0, 0.0, vol, ins, Signal{ .instrument = &linear_env.instrument });
    // print("Here, init osc {*}\n", .{osc_.instrument});
    return &osc_.instrument;
}

pub fn createKick(alloc: Allocator, t0: f32, vol: f32, f: f32, v: f32) !*Instrument {
    var ins = [_]Signal{
        .{ .constant = f },
        .{ .constant = v },
    };
    const KF = FF(kickFreq, .{ f32, f32 }, null);
    var kick_freq = try KF.init(alloc, t0, 0.0, 1.0, ins, null);
    // var kick_freq = try FF(kickFreq, 2).init(alloc, t0, 0.0, 1.0, ins);

    const K = FF(osc, .{KF}, null);
    var kick = try K.init(alloc, t0, 0.0, vol, [1]Signal{.{ .instrument = &kick_freq.instrument }}, null);
    // print("Here, init kick {*}\n", .{kick.instrument});
    return &kick.instrument;
}

pub fn fullKick(t: f32, f: f32, v: f32) f32 {
    const ff: f32 = f / std.math.pow(f32, (t + 0.001), v);
    return osc(t, ff);
}

// Single function kick to test performance
pub fn createFastKick(alloc: Allocator, t0: f32, vol: f32, f: f32, v: f32) !*Instrument {
    var ins = [_]Signal{
        .{ .constant = f },
        .{ .constant = v },
    };
    const KF = FF(fullKick, .{ f32, f32 }, null);
    var kick_freq = try KF.init(alloc, t0, 0.0, vol, ins, null);
    return &kick_freq.instrument;
}

pub fn benchmarkInstrument(instr: *Instrument, n_frames: u32) f32 {
    var begin = std.time.nanoTimestamp();
    var i: u32 = 0;
    var buf: []const f32 = undefined;
    while (i < 10000) : (i += 1) {
        var t0: f32 = @intToFloat(f32, i) * (G.sec_per_frame * @intToFloat(f32, n_frames));
        buf = instr.play(t0, n_frames);
        // print("max{}\n", .{std.mem.max(f32, buf)});
        // print("min{}\n", .{std.mem.min(f32, buf)});
    }
    var end = std.time.nanoTimestamp();
    print("buf:{} {} {} {} {}\n", .{ buf[0], buf[1], buf[2], buf[3], buf[4] });
    return @intToFloat(f32, (end - begin)) / 1000000000.0;
}

test "kick" {
    var alloc = std.testing.allocator;
    // fast kick
    var kick_f_i = try createFastKick(alloc, 0.3, 0.3, 100, 0.45);
    defer kick_f_i.deinit(alloc);
    var time = benchmarkInstrument(kick_f_i, 200);
    print("Time: {}\n", .{time});

    var kick_i = try createKick(alloc, 0.3, 0.3, 100, 0.45);
    // var kick_i = try createOsc(alloc, 0.3, 0.3, 100);
    defer kick_i.deinit(alloc);
    time = benchmarkInstrument(kick_i, 200);
    print("Time: {}\n", .{time});
}

test "comptime loop" {
    comptime var l: u32 = 0;
    comptime var k: u32 = 0;
    inline while (l < 3) : (l += 1) {
        k += l * l;
    }
    print("k={}\n", .{k});
}
