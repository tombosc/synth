const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("server", "src/server.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    exe.linkSystemLibrary("soundio");
    exe.linkLibC();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const files = [_][]const u8{
        "src/server.zig", "src/instruments.zig",
    };
    for (files) |f| {
        const exe_tests = b.addTest(f);
        exe_tests.setTarget(target);
        exe_tests.setBuildMode(mode);
        test_step.dependOn(&exe_tests.step);
    }

    const install_exe = b.addInstallArtifact(exe);
    b.getInstallStep().dependOn(&install_exe.step);
}
