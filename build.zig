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

    const exe = b.addExecutable(.{
        .name = "shapes",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

//    const core_platform = b.option(Platform, "core_platform", "mach core platform to use") orelse Platform.fromTarget(target.result);
//    const build_options = b.addOptions();
  //  build_options.addOption(Platform, "core_platform", core_platform);

    // Add Mach dependency
    const mach_dep = b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
    });
//    mach_dep.module("mach").addImport("build-options", build_options.createModule());
    exe.root_module.addImport("mach", mach_dep.module("mach"));

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
