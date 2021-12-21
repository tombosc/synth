const c = @cImport({
    @cInclude("soundio/soundio.h");
});

/// Convert an error int code to an error type
/// (from https://ziglang.org/learn/overview/)
pub fn sio_err(err: c_int) !void {
    switch (@intToEnum(c.SoundIoError, err)) {
        c.SoundIoError.None => {},
        c.SoundIoError.NoMem => return error.NoMem,
        c.SoundIoError.InitAudioBackend => return error.InitAudioBackend,
        c.SoundIoError.SystemResources => return error.SystemResources,
        c.SoundIoError.OpeningDevice => return error.OpeningDevice,
        c.SoundIoError.NoSuchDevice => return error.NoSuchDevice,
        c.SoundIoError.Invalid => return error.Invalid,
        c.SoundIoError.BackendUnavailable => return error.BackendUnavailable,
        c.SoundIoError.Streaming => return error.Streaming,
        c.SoundIoError.IncompatibleDevice => return error.IncompatibleDevice,
        c.SoundIoError.NoSuchClient => return error.NoSuchClient,
        c.SoundIoError.IncompatibleBackend => return error.IncompatibleBackend,
        c.SoundIoError.BackendDisconnected => return error.BackendDisconnected,
        c.SoundIoError.Interrupted => return error.Interrupted,
        c.SoundIoError.Underflow => return error.Underflow,
        c.SoundIoError.EncodingString => return error.EncodingString,
        _ => return error.Unknown,
    }
}
