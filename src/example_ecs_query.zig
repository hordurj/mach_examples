//! Testing the ECS system.
const std = @import("std");
const mach = @import("mach");
pub const modules = .{ Game, Shape };

const Game = struct {
    pub const Mod = mach.Mod(@This());
    pub const name = .game;
    pub const components = .{
        .name = .{ .type = []const u8 },
        .location = .{ .type = Location },
        .rotation = .{ .type = Rotation },
        .health = .{ .type = f32 },
        .is_monster = .{ .type = void },
    };
    pub const systems = .{
        .tick = .{ .handler = tick },
    };
    fn tick(self: *Mod) void {
        _ = self;
    }
};

const Shape = struct {
    pub const Mod = mach.Mod(@This());
    pub const name = .shape;
    pub const components = .{
        .name = .{ .type = []const u8 },
        .location = .{ .type = Location },
        .rotation = .{ .type = Rotation },
    };
    pub const systems = .{
        .tick = .{ .handler = tick },
    };
    fn tick(self: *Mod) void {
        _ = self;
    }
};

const Location = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

const Rotation = struct { degrees: f32 };

fn queryFunction(entities: *mach.Entities.Mod) !void {
    var q = try entities.query(.{ .ids = mach.Entities.Mod.read(.id), .rotations = Game.Mod.read(.rotation) });
    var idx: u32 = 0;
    var q_count: u32 = 0;
    while (q.next()) |v| {
        q_count += 1;
        // std.debug.print("Query {} results: {}\n", .{q_count, v.ids.len});
        for (v.ids, v.rotations) |_, _| {
            idx += 1;
            if (idx > 1) {
                return;
            }
        }
    }
}

fn queryFunction2(entities: *mach.Entities.Mod) !void {
    var q = try entities.query(.{ .ids = mach.Entities.Mod.read(.id), .rotations = Game.Mod.read(.rotation) });
    var idx: u64 = 0;
    var count: u32 = 0;
    while (q.next()) |v| {
        for (v.ids, v.rotations) |id, _| {
            idx += id;
            count += 1;
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    //-------------------------------------------------------------------------
    // Create a world.
    var world: *mach.Modules = try allocator.create(mach.Modules);
    try world.init(allocator);
    defer {
        world.deinit(allocator);
        allocator.destroy(world);
    }

    std.debug.print("{} {}\n", .{ mach.Modules, modules });
    var entities = &world.mod.entities;
    var game = &world.mod.game;
    var shape = &world.mod.shape;

    {
        const player1 = try entities.new();
        try game.set(player1, .name, "jane");
        try game.set(player1, .location, .{ .x = 10.0, .y = 13.1, .z = 21.0 });
        try game.set(player1, .rotation, .{ .degrees = 90 });
        try game.set(player1, .health, 100.0 );
        try shape.set(player1, .rotation, .{ .degrees = 90 });
    }
    {
        const player1 = try entities.new();
        try game.set(player1, .location, .{ .x = 10.0, .y = 13.1, .z = 21.0 });
        try game.set(player1, .rotation, .{ .degrees = 90 });
    }

    const call_function = false;

    for (0..5) |_| {
        std.debug.print("Query 1: ", .{});
        if (call_function) {
            try queryFunction(entities);
        } else { //query: {
            var q = try entities.query(.{ .ids = mach.Entities.Mod.read(.id), .rotations = Game.Mod.read(.rotation) });
            defer { 
                if (q.dynamic.entities.active_queries.items.len > 0 and !q.dynamic.entities.active_queries.items[q.dynamic.index].finished) {
                    while (q.next()) |_| {}
                }                
            }
            var idx: u32 = 0;
            var q_count: u32 = 0;
            while (q.next()) |v| {
                q_count += 1;
                //std.debug.print("Query {} results: {}\n", .{q_count, v.ids.len});
                for (v.ids, v.rotations) |_, _| {
                    idx += 1;
                    if (idx > 1) {
                        // break :query;
                    }
                }
            }
        }
        std.debug.print("Query 2: ", .{});
        try queryFunction2(entities);
    }
}
