const std = @import("std");
const E = enum {
    a,
    b,
    c
};
pub fn main() !void {
    const a = E.a;
    const b = E.b;

    std.debug.print("{} {}\n", .{@as(u32,@intFromEnum(a)),@as(u32,@intFromEnum(b))});
    if (@intFromEnum(a)>@intFromEnum(b)) {
        std.debug.print("yes\n", .{});
    } else {
        std.debug.print("no\n", .{});
    }

    const c = .{2.0, 4.0};
    std.debug.print("{}\n", .{@TypeOf(c)});
}