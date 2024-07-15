// This file is just a sandbox to learn about various things in zig.
const std = @import("std");

const Entity = struct {
    id: u32,
    value: u32,

    fn setValue(self: *Entity, v: u32) void {
        self.value = v;
    }
};

pub fn getEntityValue(self: *Entity) u32 {
    return self.value;
}

const Vec4 = struct {
    v: [4]f32,
};

pub fn rgb(r: anytype, g: anytype, b: anytype) Vec4 {
    if (@TypeOf(r) == @TypeOf(g) and @TypeOf(g) == @TypeOf(b)) {
        switch (@typeInfo(@TypeOf(r))) {
            .ComptimeInt, .Int => {
                return Vec4{.v = [_]f32{
                    @as(f32, @floatFromInt(r)) / 255.0,
                    @as(f32, @floatFromInt(g)) / 255.0,
                    @as(f32, @floatFromInt(b)) / 255.0,
                    1.0
                }};
            },   
            .ComptimeFloat, .Float => {
                return Vec4{.v = [_]f32{r, g, b, 1.0}};
            },
            else =>
            {
                @compileError("r,g,b need to be Int or Float");
            },
        }
    } else {
        @compileError("r,g,b need to be of same type.");
    }
}


pub fn main() void {
    var e = Entity{.id = 0, .value = 0};
    e.setValue(10);

    // obj.value syntax is only valid for functions inside a struct
    //const v = e.getEntityValue();
    //const p = &e;
    //const v = p.getEntityValue();
    const v = getEntityValue(&e);
    std.debug.print("{}\n", .{v});

    const p = &e;
    p.setValue(20);
    std.debug.print("{}\n", .{getEntityValue(p)});

    std.debug.print("rgb int: {}\n", .{rgb(255, 100, 255)});
    std.debug.print("rgb float: {}\n", .{rgb(1.0, 0.5, 0.8)});
}
