const c = @cImport({
    @cInclude("soundio/soundio.h");
});
const std = @import("std");
const print = @import("std").debug.print;
const panic = @import("std").debug.panic;
const math = @import("std").math;
const sio_err = @import("sio_errors.zig").sio_err;

var seconds_offset: f32 = 0.0;

pub fn main() !u8 {
    try start_server(1);
    return 0;
}

/// For now, only create soundio context and pass callback
/// (Taken from https://ziglang.org/learn/overview/ mostly)
pub fn start_server(verbose: u8) !void {
    const soundio: *c.SoundIo = c.soundio_create();
    defer c.soundio_destroy(soundio);

    // const backend = c.SoundIoBackend.Alsa;
    // default is "PulseAudio", but it is slow!
    const backend = c.SoundIoBackend.PulseAudio;
    try sio_err(c.soundio_connect_backend(soundio, backend));

    const backend_name = c.soundio_backend_name(soundio.current_backend);
    if (verbose > 0)
        print("Backend={s}\n", .{backend_name});

    c.soundio_flush_events(soundio);

    const device_index = c.soundio_default_output_device_index(soundio);
    if (device_index < 0) {
        panic("No output device found\n", .{});
    } else if (verbose > 0) {
        print("Device index : {}\n", .{device_index});
    }

    const device: *c.SoundIoDevice = c.soundio_get_output_device(soundio, device_index);
    defer c.soundio_device_unref(device);
    if (verbose > 0)
        print("output device: {}\n", .{device.name});

    const outstream: *c.SoundIoOutStream = c.soundio_outstream_create(device) orelse
        return error.OutOfMemory;
    defer c.soundio_outstream_destroy(outstream);

    outstream.sample_rate = 44100;
    // idk how to set software latency right now
    // outstream.software_latency = 0.001;
    outstream.format = c.enum_SoundIoFormat.Float32LE; // macro = c.SoundIoFormatFloat32NE
    if (!c.soundio_device_supports_format(device, outstream.format)) {
        print("Format {} not supported!\n", .{c.soundio_format_string(outstream.format)});
    }

    outstream.write_callback = write_callback;
    try sio_err(c.soundio_outstream_open(outstream));
    var total_latency: f64 = 0.0;
    var output_latency = c.soundio_outstream_get_latency(outstream, &total_latency);
    if (verbose > 0) {
        print("Software latency {}\n", .{outstream.software_latency});
        print("Latency {}\n", .{total_latency});
    }

    if (outstream.layout_error > 0) {
        print("unable to set channel layout\n", .{});
    }

    sio_err(c.soundio_outstream_start(outstream)) catch |err| {
        panic("Unable to start stream: {}", .{@errorName(err)});
    };

    while (true) {
        print("In the loop\n", .{});
        c.soundio_wait_events(soundio);
    }
    return 0;
}

fn write_callback(
    maybe_ostream: ?*c.SoundIoOutStream,
    frame_count_min: c_int,
    frame_count_max: c_int,
) callconv(.C) void {
    print("Call write_callback()\n", .{});
    const ostream = maybe_ostream.?;
    const layout = ostream.layout;
    const float_sample_rate = ostream.sample_rate;
    const seconds_per_frame: f32 = 1.0 / @intToFloat(f32, float_sample_rate);
    // var areas: [*]c.SoundIoChannelArea = null;
    // var areas: [2]c.SoundIoChannelArea = [_]c.SoundIoChannelArea{ null, null };
    var opt_areas: ?[*]c.SoundIoChannelArea = null;
    var frames_left = @intCast(u32, frame_count_max);
    var err: c_int = 0;

    while (frames_left > 0) {
        var frame_count: c_int = @intCast(c_int, frames_left);
        // print("Frame count {} SR {} min {} max {}\n", .{ frame_count, float_sample_rate, frame_count_min, frame_count_max });
        err = c.soundio_outstream_begin_write(ostream, &opt_areas, &frame_count);
        // frame_count got updated!
        if (err > 0) {
            panic("Error begin write", .{});
        }
        if (frame_count <= 0) {
            break;
        }
        const rps = 440.0 * 2.0 * std.math.pi;
        var i: c_int = 0;
        if (opt_areas) |areas| {
            while (i < frame_count) : (i += 1) {
                const fi = @intToFloat(f32, i);
                var sample: f32 = math.sin((seconds_offset + fi * seconds_per_frame) * rps);
                var ch: u8 = 0;
                while (ch < layout.channel_count) : (ch += 1) {
                    const step = areas[ch].step;
                    // [*]T supports pointer arithmetic (but not *T), hence 1st cast
                    const ptr = @ptrCast([*]u8, areas[ch].ptr) + @intCast(usize, step * i);
                    // we use Float32LE here
                    @ptrCast(*f32, @alignCast(@alignOf(f32), ptr)).* = sample;
                }
            }
        }
        var fframe_count = @intToFloat(f32, frame_count);
        seconds_offset = math.mod(f32, seconds_offset + fframe_count * seconds_per_frame, 1.0) catch unreachable;
        err = c.soundio_outstream_end_write(ostream);
        if (err > 0) {
            panic("Error write \n", .{});
        }
        frames_left -= @intCast(u32, frame_count);
    }
    _ = c.soundio_outstream_pause(ostream, false);
}
