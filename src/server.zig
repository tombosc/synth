const c = @cImport({
    @cInclude("soundio/soundio.h");
});
const std = @import("std");
const print = std.debug.print;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const sio_err = @import("sio_errors.zig").sio_err;
const I = @import("instruments.zig");
const Instrument = I.Instrument;
const Signal = I.Signal;
const FF = I.FF;
const G = @import("global_config.zig");
const expect = std.testing.expect;
const Order = std.math.Order;

fn beginsSooner(context: void, a: *Instrument, b: *Instrument) Order {
    _ = context;
    if (a.approx_start_time == b.approx_start_time) {
        return Order.eq;
    } else if (a.approx_start_time < b.approx_start_time) {
        return Order.lt;
    }
    return Order.gt;
}

const NoteQueue = std.PriorityQueue(*Instrument, void, beginsSooner);

const GlobalState = struct {
    bufL: []f32,
    bufR: []f32,
    // (constant) number of frames written at once is a multiple of n_frames
    // this creates time quantization
    n_frames: u32,
    // number of frames that are ready to read in bufL, bufR
    n_frames_ready: u32 = 0,
    // for now, the way latency / frequency of writes is dealt with:
    // 1. write_callback "requests" a certain number of frames, frame_count_max
    //    it is written in n_frames_requested
    // 2. play() then prepares as much frames as requested.
    n_frames_requested: u32 = 0,
    // seconds of audio actually written to audio buffer by write_callback
    // crucial to know where to start again to play new sounds
    global_t: f32 = 0,

    // /// mimicks what happens in write_callback
    // fn test_consume_ready(g_state: *GlobalState, n_max: u32) void {
    //     if (n_max > g_state.n_frames_ready)
    //         g_state.n_frames_requested += n_max - g_state.n_frames_ready;
    //     // copy buffer
    //     g_state.n_frames_ready = 0;
    // }
};

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var noteQueue = NoteQueue.init(allocator, undefined);
    var instr1 = try I.createOsc(allocator, 1.0, 0.1, 440.0);
    var instr2 = try I.createOsc(allocator, 1.0, 0.05, 440.0 * (4.0 / 3.0));
    var instr3 = try I.createOsc(allocator, 1.0, 0.025, 440.0 * (5.0 / 3.0));
    try expect(instr1 != instr2);

    _ = instr1;
    _ = instr2;
    _ = instr3;
    try noteQueue.add(instr1);
    try noteQueue.add(instr2);
    try noteQueue.add(instr3);
    // try noteQueue.add(&instr2.instrument);
    // try noteQueue.add(&instr3.instrument);
    // try noteQueue.add(&instr4.instrument);
    // try noteQueue.add(&instr5.instrument);
    // try noteQueue.add(&instr6.instrument);

    var kick_i = try I.createKick(allocator, 0.3, 0.3, 100, 0.45);
    try noteQueue.add(kick_i);
    _ = kick_i;
    try start_server(allocator, 200, &noteQueue);
    return 0;
}

inline fn print_vb(comptime fmt: []const u8, args: anytype, comptime verbose_level: u8) void {
    if (G.verbose >= verbose_level) {
        print(fmt, args);
    }
}

pub fn play(
    alloc: Allocator,
    g_state: *GlobalState,
    noteQueue: *NoteQueue,
) !void {
    if (g_state.n_frames_ready > 0) { // data hasn't been read yet!
        print_vb("NOT READ DATA!\n", .{}, 3);
        return;
    }

    // only play multiples of g_state.n_frame. Necessary? sounds like a good idea for quantization purposes?
    const additional = (g_state.n_frames_requested) / g_state.n_frames;
    const frames_to_play = g_state.n_frames * (additional + 1);
    print_vb("play(): #frames={} \n", .{frames_to_play}, 3);
    // const frames_to_play = g_state.n_frames * additional;
    const frames_left = g_state.n_frames_requested % g_state.n_frames;
    // play instruments, mix, etc.
    // first, zero out the buffers
    // print("PLAY!!! {} {}\n", .{ g_state.bufL.len, frames_to_play });
    std.mem.set(f32, g_state.bufL[0..frames_to_play], 0);
    std.mem.set(f32, g_state.bufR[0..frames_to_play], 0);
    // there are 2 cases when we don't play anything
    // - if there is no note in the queue
    // - if the closest note in time is still to far in time
    var dont_play: bool = false;
    // tol: tolerance to decide if we can play the note or not
    const tol = G.sec_per_frame * @intToFloat(f32, g_state.n_frames);
    while (noteQueue.peek()) |elem| {
        print_vb("Time {}, ftp {}\n", .{ g_state.global_t, frames_to_play }, 3);
        if (elem.over) {
            // remove notes that are over
            alloc.destroy(noteQueue.remove());
            print_vb("Stop playing instrument={} at time t={}\n", .{ elem, g_state.global_t }, 1);
        } else {
            // check that the next note to play is not too far in time
            var time_delta = elem.approx_start_time - g_state.global_t;
            if (time_delta > tol) {
                // if it is too far in time, don't play anything
                dont_play = true;
            }
            break;
        }
    }
    if (!dont_play) {
        // it'd be nice to iterate in the order of priority, but idk how to do
        // that
        var maybe_it = noteQueue.iterator();
        while (maybe_it.next()) |it| {
            const time_delta = g_state.global_t - it.approx_start_time;
            if (time_delta > tol) {
                const instr_buf = it.play(time_delta, frames_to_play);
                for (instr_buf) |*b, i| {
                    g_state.bufL[i] += b.* * it.volume;
                    g_state.bufR[i] += b.* * it.volume;
                }
                print_vb("Play {p} at time {}\n", .{ it, g_state.global_t }, 3);
            }
        }
    }
    // print("MAX {}\n", .{std.mem.max(f32, g_state.bufL[0..frames_to_play])});
    // update global state
    g_state.n_frames_ready = frames_to_play;
    g_state.global_t += @intToFloat(f32, frames_to_play) / @intToFloat(f32, G.sample_rate);
    g_state.n_frames_requested = frames_left;
    print_vb("End play: preped {}, left {}\n", .{ g_state.n_frames_ready, g_state.n_frames_requested }, 3);
}

// test "play" {
//     var alloc = std.testing.allocator;
//     var bufL = [_]f32{0.0} ** (10 * 5);
//     var bufR = [_]f32{0.0} ** (10 * 5);
//     var g_state = GlobalState{
//         .bufL = &bufL,
//         .bufR = &bufR,
//         .n_frames = 10,
//     };
//     g_state.test_consume_ready(14);
//     // nothing prepared, requests 14; play() prepares 20
//     // print("1a {} {}\n", .{ g_state.n_frames_ready, g_state.n_frames_requested });
//     try play(alloc, &g_state);
//     print("1b {} {}\n", .{ g_state.n_frames_ready, g_state.n_frames_requested });
//     // try expect(g_state.n_frames_ready == 20);

//     g_state.test_consume_ready(18);
//     // only plays 10
//     // print("2a {} {}\n", .{ g_state.n_frames_ready, g_state.n_frames_requested });
//     try play(alloc, &g_state);
//     print("2b {} {}\n", .{ g_state.n_frames_ready, g_state.n_frames_requested });
//     // try expect(g_state.n_frames_ready == 10);

//     g_state.test_consume_ready(40);
//     // print("3a {} {}\n", .{ g_state.n_frames_ready, g_state.n_frames_requested });
//     try play(alloc, &g_state);
//     print("3b {} {}\n", .{ g_state.n_frames_ready, g_state.n_frames_requested });
//     // try expect(g_state.n_frames_ready == 20);
// }

/// For now, only create soundio context and pass callback
/// (Taken from https://ziglang.org/learn/overview/ mostly)
pub fn start_server(
    alloc: Allocator,
    n_min_frames: u32,
    noteQueue: *NoteQueue,
) !void {
    const soundio: *c.SoundIo = c.soundio_create();
    defer c.soundio_destroy(soundio);

    const frame_size = n_min_frames;
    const K: u32 = 10000;
    var bufL = try alloc.alloc(f32, K);
    var bufR = try alloc.alloc(f32, K);
    var g_state = GlobalState{
        .bufL = bufL,
        .bufR = bufR,
        .n_frames = frame_size,
    };

    // const backend = c.SoundIoBackend.Alsa;
    // default is "PulseAudio", but it is slow!
    // print("{}\n", .{@typeInfo(c.enum_SoundIoBackend)});
    // const backend = c.enum_SoundIoBackend.PulseAudio;
    // const backend: c.enum_SoundIoBackend = c.SoundIoBackendPulseAudio;
    const backend = c.SoundIoBackendPulseAudio;
    try sio_err(c.soundio_connect_backend(soundio, backend));

    const backend_name = c.soundio_backend_name(soundio.current_backend);
    print_vb("Backend={s}\n", .{backend_name}, 1);

    c.soundio_flush_events(soundio);

    const device_index = c.soundio_default_output_device_index(soundio);
    if (device_index < 0) {
        panic("No output device found\n", .{});
    }
    print_vb("Device index={}\n", .{device_index}, 1);

    const device: *c.SoundIoDevice = c.soundio_get_output_device(soundio, device_index);
    defer c.soundio_device_unref(device);

    const outstream: *c.SoundIoOutStream = c.soundio_outstream_create(device) orelse
        return error.OutOfMemory;
    defer c.soundio_outstream_destroy(outstream);

    outstream.userdata = @ptrCast(?*anyopaque, &g_state);
    outstream.sample_rate = G.sample_rate;
    // the smallest I can get seems to be 0.01 on my machine.
    // this gives frame_count_max=112 most of the time, with occasionally
    // higher values up to 216
    outstream.software_latency = 0.01;
    outstream.format = c.SoundIoFormatFloat32LE; // c.SoundIoFormatFloat32NE
    if (!c.soundio_device_supports_format(device, outstream.format)) {
        print("Format {s} not supported!\n", .{c.soundio_format_string(outstream.format)});
    }

    outstream.write_callback = write_callback;
    try sio_err(c.soundio_outstream_open(outstream));
    var total_latency: f64 = 0.0;
    _ = c.soundio_outstream_get_latency(outstream, &total_latency);
    print_vb("Software latency={}\n", .{outstream.software_latency}, 1);
    print_vb("Latency={}\n", .{total_latency}, 1);

    if (outstream.layout_error > 0) {
        print("unable to set channel layout\n", .{});
    }

    try sio_err(c.soundio_outstream_start(outstream));

    // the loop
    const period_time = @intToFloat(f32, frame_size) / @intToFloat(f32, G.sample_rate);
    var t: u64 = 0;
    const begin = std.time.nanoTimestamp();
    while (true) {
        print_vb("Loop\n", .{}, 3);
        t += 1;
        try play(alloc, &g_state, noteQueue);
        var end = std.time.nanoTimestamp();
        var elapsed_ns = end - begin;
        var remaining = @intToFloat(f32, t) * period_time;
        var elapsed = @intToFloat(f32, elapsed_ns) / 1e9;
        if ((remaining - elapsed) < 0) {
            print_vb("Running late!\n", .{}, 1);
        } else {
            var sleep_ns = @floatToInt(u64, @maximum(remaining - elapsed, 0) * 1e9);
            std.time.sleep(sleep_ns);
            print_vb("Sleep {}ns\n", .{sleep_ns}, 3);
        }
    }
}

fn write_callback(
    maybe_ostream: ?*c.SoundIoOutStream,
    frame_count_min: c_int,
    frame_count_max: c_int,
) callconv(.C) void {
    const ostream = maybe_ostream.?;
    var g_state = @ptrCast(*GlobalState, @alignCast(@alignOf(*GlobalState), ostream.userdata));
    print_vb("BEGIN write_callback(): frame_count_min={}, max={}\n", .{ frame_count_min, frame_count_max }, 3);
    var opt_areas: ?[*]c.SoundIoChannelArea = null;
    const fframe_count_max = @intCast(u32, frame_count_max);
    var frames_to_write = @minimum(fframe_count_max, g_state.n_frames_ready);
    var total_written: u32 = frames_to_write;
    if (fframe_count_max > frames_to_write) {
        // in this case, since we write less data than is the maximum
        // possible, we request play() to write more data at the next timestep
        g_state.n_frames_requested += fframe_count_max - frames_to_write;
    }
    var err: c_int = 0;
    const bufs = [2][]f32{ g_state.bufL, g_state.bufR };
    var offset: u32 = 0;
    while (frames_to_write > 0) {
        var frame_count: c_int = @intCast(c_int, frames_to_write);
        err = c.soundio_outstream_begin_write(ostream, &opt_areas, &frame_count);
        if (err > 0) {
            panic("Error begin_write \n", .{});
        }
        if (opt_areas) |areas| {
            var i: u32 = 0;
            const layout = ostream.layout;
            while (i < frame_count) : (i += 1) {
                var ch: u8 = 0;
                while (ch < layout.channel_count) : (ch += 1) {
                    const step = @intCast(u32, areas[ch].step);
                    // [*]T supports pointer arithmetic (but not *T), hence 1st cast
                    const ptr = @ptrCast([*]u8, areas[ch].ptr) + @intCast(usize, step * i);
                    // we use Float32LE here
                    @ptrCast(*f32, @alignCast(@alignOf(f32), ptr)).* = bufs[ch][offset + i];
                }
            }
        }
        err = c.soundio_outstream_end_write(ostream);
        if (err > 0) {
            panic("Error end_write \n", .{});
        }
        print_vb("write_cb() end loop here, {} {} {}\n", .{ frame_count_max, frame_count, frames_to_write }, 3);
        frames_to_write -= @intCast(u32, frame_count);
    }
    g_state.n_frames_ready -= total_written;
    if (g_state.n_frames_ready > 0) {
        // correct offset, since we generated data too much in advance
        // a bit wasteful, but probably necessary for real time
        g_state.global_t -= @intToFloat(f32, g_state.n_frames_ready) / @intToFloat(f32, G.sample_rate);
        g_state.n_frames_ready = 0;
    }
    _ = c.soundio_outstream_pause(ostream, false);
    print_vb("END write_callback()\n", .{}, 3);
}
