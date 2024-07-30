const std = @import("std");
pub const Platform = enum {
    glfw,
    x11,
    wayland,
    web,
    win32,

    pub fn fromTarget(target: std.Target) Platform {
        if (target.cpu.arch == .wasm32) return .web;
        return .glfw;
    }
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mach_dep = b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
        .core_platform = .win32,
    });

    // const ztracy = b.dependency("ztracy", .{
    //     .enable_ztracy = false,
    //     .enable_fibers = false,
    // });

    const examples = [_][]const u8{
        "shapes",
        "polygons",
        "physics",
        "events",
        //        "ecs"
    };

    for (examples) |example| {
        var filename_buf: [255]u8 = undefined;
        var run_command_buf: [255]u8 = undefined;
        var run_command_description_buf: [255]u8 = undefined;

        const filename = try std.fmt.bufPrint(&filename_buf, "src/example_{s}.zig", .{example});
        const run_command = try std.fmt.bufPrint(&run_command_buf, "run-{s}", .{example});
        const run_command_description = try std.fmt.bufPrint(&run_command_description_buf, "Run {s}", .{example});

        const exe = b.addExecutable(.{
            .name = example,
            .root_source_file = b.path(filename),
            .target = target,
            .optimize = optimize,
        });
        b.installArtifact(exe);

        //    mach_dep.module("mach").addImport("build-options", build_options.createModule());
        exe.root_module.addImport("mach", mach_dep.module("mach"));
        //exe.root_module.addImport("ztracy", ztracy.module("root"));
        //exe.linkLibrary(ztracy.artifact("tracy"));

        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step(run_command, run_command_description);
        run_step.dependOn(&run_cmd.step);
    }

    {
        const exe = b.addExecutable(.{
            .name = "zig_basics",
            .root_source_file = b.path("src/examples/zig_basics.zig"),
            .target = target,
            .optimize = optimize,
        });

        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step("run-zig-basics", "Run the zig basics");
        run_step.dependOn(&run_cmd.step);
    }
}
