const std = @import("std");
const I = @import("instruments.zig");
const Instrument = I.Instrument;
const G = @import("global_config.zig");
const print = std.debug.print;

const InstrumentList = std.ArrayList(*Instrument);

pub fn benchmarkInstruments(instr: InstrumentList, n_frames: u32) f32 {
    var begin = std.time.nanoTimestamp();
    var i: u32 = 0;
    var buf: []const f32 = undefined;
    var S: f32 = 0.0;
    while (i < 1000) : (i += 1) {
        for (instr.items) |instrument| {
            var t0: f32 = @intToFloat(f32, i) * (G.sec_per_frame * @intToFloat(f32, n_frames));
            buf = instrument.play(t0, n_frames);
            for (buf) |b| {
                S += b / 10;
            }
        }
    }
    var end = std.time.nanoTimestamp();
    print("buf:{} {} {} {} {} {}\n", .{ buf[0], buf[1], buf[2], buf[3], buf[4], S });
    return @intToFloat(f32, (end - begin)) / 1000000000.0;
}

pub fn main() !u8 {
    var alloc = std.testing.allocator;
    // fast kick
    const n_instr: u32 = 50;
    var i: u32 = 0;
    var static_instruments = InstrumentList.init(alloc);
    defer static_instruments.deinit();
    var dynamic_instruments = InstrumentList.init(alloc);
    defer dynamic_instruments.deinit();
    while (i < n_instr) : (i += 1) {
        const fi = @intToFloat(f32, i);
        var static_kick = try I.createKick(alloc, 0.3, 0.3, 100 * fi, 0.45 + (fi / 100.0), true);
        var dynamic_kick = try I.createKick(alloc, 0.3, 0.3, 100 * fi, 0.45 + (fi / 100.0), false);
        // defer static_kick.deinit(alloc);
        // defer dynamic_kick.deinit(alloc);
        try static_instruments.append(static_kick);
        try dynamic_instruments.append(dynamic_kick);
    }

    var time = benchmarkInstruments(dynamic_instruments, 200);
    print("Time dynamic kick: {}\n", .{time});

    time = benchmarkInstruments(static_instruments, 200);
    print("Time static kick: {}\n", .{time});

    for (static_instruments.items) |instrument|
        instrument.deinit(alloc);
    for (dynamic_instruments.items) |instrument|
        instrument.deinit(alloc);
    return 0;
}
