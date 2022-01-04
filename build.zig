const std = @import("std");
const deps = @import("./deps.zig");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe_names_and_files = [2][2][]const u8{
        [2][]const u8{ "server", "src/server.zig" },
        [2][]const u8{ "benchmark", "src/benchmarks.zig" },
    };

    for (exe_names_and_files) |e| {
        const exe = b.addExecutable(e[0], e[1]);
        exe.setTarget(target);
        exe.setBuildMode(mode);
        deps.addAllTo(exe);
        exe.install();

        const run_cmd = exe.run();
        exe.linkSystemLibrary("soundio");
        exe.linkLibC();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        var buf_name_cmd: [100]u8 = undefined;
        var buf_explanation: [100]u8 = undefined;
        const name_cmd = std.fmt.bufPrint(&buf_name_cmd, "run_{s}", .{e[0]}) catch {
            continue;
        };
        const explanation = std.fmt.bufPrint(&buf_explanation, "Run {s}", .{e[1]}) catch {
            continue;
        };
        const run_step = b.step(name_cmd, explanation);
        run_step.dependOn(&run_cmd.step);
        const install_exe = b.addInstallArtifact(exe);
        b.getInstallStep().dependOn(&install_exe.step);
    }

    // const bench_step = b.step("benchmark", "Run benchmarks");
    // bench_step.dependOn(&exe_bench.step);

    const test_step = b.step("test", "Run unit tests");
    const files = [_][]const u8{
        "src/server.zig", "src/instruments.zig", "src/network.zig",
    };
    for (files) |f| {
        const exe_tests = b.addTest(f);
        exe_tests.setTarget(target);
        exe_tests.setBuildMode(mode);
        deps.addAllTo(exe_tests);
        test_step.dependOn(&exe_tests.step);
    }
}
