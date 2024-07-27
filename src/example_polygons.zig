const std = @import("std");
const mach = @import("mach");

pub const App = @import("examples/polygon_app.zig");
pub const Shapes = @import("shapes/main.zig");
pub const gm = @import("geometry.zig");

pub const modules = .{
    mach.Core,
    Shapes,
    App,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var polygon1 = gm.Polygon.init(allocator);
    defer polygon1.deinit();
    var polygon2 = gm.Polygon.init(allocator);
    defer polygon2.deinit();

    try polygon1.add(mach.math.vec2(1.0, 2.0));
    try polygon1.add(mach.math.vec2(2.0, 2.0));
    try polygon1.add(mach.math.vec2(3.0, 2.0));

    try polygon2.add(mach.math.vec2(5.0, 2.0));
    try polygon2.add(mach.math.vec2(6.0, 2.0));
    try polygon2.add(mach.math.vec2(7.0, 2.0));

    std.debug.print("Right most {}\n", .{polygon1.rightmostVertex()});
    std.debug.print("Polygon 1 before {any}\n", .{polygon1.indices.items});
    try polygon1.insertPolygon(1, &polygon2);
    std.debug.print("Polygon 1 after {any}\n", .{polygon1.indices.items});
    std.debug.print("Polygon 1 vertices after {any}\n", .{polygon1.vertices.items});
    std.debug.print("Right most {}\n", .{polygon1.rightmostVertex()});

    var app = try mach.App.init(allocator, .app);
    defer app.deinit(allocator);
    try app.run(.{ .allocator = allocator, .power_preference = .high_performance });

}
