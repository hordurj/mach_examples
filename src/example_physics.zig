const std = @import("std");
const mach = @import("mach");

pub const App = @import("examples/physics_app.zig");
pub const Shapes = @import("shapes/main.zig");

pub const modules = .{
    mach.Core,
    Shapes,
    App,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try mach.App.init(allocator, .app);
    defer app.deinit(allocator);
    try app.run(.{ .allocator = allocator, .power_preference = .high_performance });

}
