pub const use_sysgpu = true;
const std = @import("std");
const mach = @import("mach");

pub const App = @import("examples/shapes_app.zig");
pub const Shapes = @import("shapes/main.zig");

pub const modules = .{
    mach.Core,
    Shapes,
    App,
};

pub fn main() !void {
    try mach.core.initModule();
    while (try mach.core.tick()) {}
}
