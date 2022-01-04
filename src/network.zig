const std = @import("std");
const network = @import("network");
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const log = std.math.log;
const G = @import("global_config.zig");
const I = @import("instruments.zig");

const Note = struct {
    instr_id: u8,
    note: u8,
    octave: u8,

    fn getFreq(self: Note) f32 {
        var log_f = @intToFloat(f32, self.note) * log(f32, std.math.e, 2.0) / 24 + log(f32, std.math.e, 16.0);
        const f: f32 = std.math.exp(log_f) * std.math.pow(f32, @intToFloat(f32, self.octave) + 1.0, 2);
        print("Converted freq {}\n", .{f});
        return f;
    }
};

const MsgType = enum(u8) {
    note_start = 0,
    note_end = 1,
    tweak_param = 4,
};

const DecodeError = error{
    WrongMsgType,
};

/// Intermediary representation of sounds that can be logged and serialized, to be replayed, edited, etc.
const Event = union(enum) {
    note_start: Note,
    note_end, // not impl
    tweak_param, // not impl

    fn fromBytes(raw_data: []const u8) DecodeError!Event {
        const msg_type = @intToEnum(MsgType, raw_data[0]);
        return switch (msg_type) {
            .note_start => Event{ .note_start = Note{
                .instr_id = raw_data[1],
                .note = raw_data[2],
                .octave = raw_data[3],
            } },
            .note_end => Event.note_end,
            .tweak_param => Event.tweak_param,
        };
    }

    fn process(self: *Event, alloc: Allocator, events: *I.NoteQueue) !void {
        switch (self.*) {
            .note_start => {
                const N = self.note_start;
                const now = G.nowSeconds() + 0.1;
                var new_instrument: ?*I.Instrument = null;
                var f = N.getFreq();
                if (N.instr_id == 0) {
                    print("New Kick at t={}\n", .{now});
                    new_instrument = try I.createKick(alloc, now, 0.5, f, 0.45, true);
                } else {
                    print("Unrecognized instr {}\n", .{N.instr_id});
                }
                if (new_instrument) |ii| {
                    try events.add(ii);
                    // TODO handle error
                }
            },
            else => {
                print("Not implemented!\n", .{});
            },
        }
    }
};

var buf = [_]u8{0} ** 100;

/// TODO find a better name for instruments...
pub fn listenToEvents(alloc: Allocator, events: *I.NoteQueue) !void {
    try network.init();
    defer network.deinit();
    var sock = try network.Socket.create(.ipv4, .udp);
    defer sock.close();
    try sock.bindToPort(4321);

    // parse messages
    while (true) {
        var size_received = try sock.receive(&buf);
        var data = buf[0..size_received];
        print("Received raw {s}\n", .{data});
        var event = try Event.fromBytes(data);
        print("is event {}\n", .{event});
        try event.process(alloc, events);
    }
}

test {
    //

}
