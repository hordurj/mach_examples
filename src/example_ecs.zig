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

const Players = struct { name: []const u8, location: Location, rotation: Rotation, is_monster: void };
const EntityList = std.MultiArrayList(Players);

const ztracy = @import("ztracy");

fn queryFunction(entities: *mach.Entities.Mod) !void {
    var q = try entities.query(.{ .ids = mach.Entities.Mod.read(.id), .rotations = Game.Mod.read(.rotation) });
    var idx: u32 = 0;
    while (q.next()) |v| {
        for (v.ids, v.rotations) |id, rotation| {
            _ = rotation;
            _ = id;
            idx += 1;
            if (idx > 1) {
                std.debug.print("Break\n", .{});
                return;
            }
        }
    }
    std.debug.print("Count 1 {}\n", .{idx});
}

fn queryFunction2(entities: *mach.Entities.Mod) !void {
    var q = try entities.query(.{ .ids = mach.Entities.Mod.read(.id), .rotations = Game.Mod.read(.rotation) });
    var idx: u64 = 0;
    var count: u32 = 0;
    while (q.next()) |v| {
        for (v.ids, v.rotations) |id, rotation| {
            _ = rotation;
            idx += id;
            count += 1;
        }
    }
    std.debug.print("Count 2: {} {} \n", .{ count, idx });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var simple_world = EntityList{};
    var i: f32 = 137.0;
    defer simple_world.deinit(allocator);
    {
        //        const tracy_zone = ztracy.ZoneNS(@src(), "ECS Test", 0x00_ff_00_00);
        const tracy_zone = ztracy.ZoneN(@src(), "Simple ECS Test");
        defer tracy_zone.End();

        for (0..10) |_| {
            const t_start: i64 = std.time.microTimestamp();
            const N = 1000;
            for (0..N) |_| {
                const zone_e = ztracy.ZoneN(@src(), "Create entity");
                defer zone_e.End();

                try simple_world.append(allocator, .{ .name = "jane", .location = .{ .x = 10.0, .y = 13.1, .z = 21.0 }, .rotation = .{ .degrees = i }, .is_monster = {} });

                i = @mod(i * 3147.51, 360.0);
            }
            const t: f32 = @floatFromInt(std.time.microTimestamp() - t_start);
            std.debug.print("Time per creation {d:.4} us total {d:.1}\n", .{ t / N, t });
        }
    }

    std.debug.print("Number of entities {} {} \n", .{ simple_world.len, simple_world.items(.rotation)[3] });

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
        //        const tracy_zone = ztracy.ZoneNS(@src(), "ECS Test", 0x00_ff_00_00);
        const tracy_zone = ztracy.ZoneN(@src(), "ECS Test");
        defer tracy_zone.End();
        {
            const player1 = try entities.new();
            {
                const zone = ztracy.ZoneNS(@src(), "Set component name", 10);
                defer zone.End();
                try game.set(player1, .name, "jane");
            }
            {
                const zone = ztracy.ZoneNS(@src(), "Set component rotation", 10);
                defer zone.End();
                try game.set(player1, .rotation, .{ .degrees = 90 });
            }
            {
                try shape.set(player1, .rotation, .{ .degrees = 90 });
            }
        }
        defer tracy_zone.End();
        {
            const player1 = try entities.new();
            {
                const zone = ztracy.ZoneNS(@src(), "Set component rotation", 10);
                defer zone.End();
                try game.set(player1, .rotation, .{ .degrees = 90 });
            }
            {
                const zone = ztracy.ZoneNS(@src(), "Set component location", 10);
                defer zone.End();
                try game.set(player1, .location, .{ .x = 10.0, .y = 13.1, .z = 21.0 });
            }
        }

        for (0..10) |_| {
            const t_start: i64 = std.time.microTimestamp();
            const N = 100;
            for (0..N) |_| {
                const zone_e = ztracy.ZoneN(@src(), "Create entity");
                defer zone_e.End();

                const player1 = try entities.new();
                {
                    const zone = ztracy.ZoneNS(@src(), "Set component name", 10);
                    defer zone.End();
                    try game.set(player1, .name, "jane");
                }

                {
                    const zone = ztracy.ZoneNS(@src(), "Set component location", 10);
                    defer zone.End();
                    try game.set(player1, .location, .{ .x = 10.0, .y = 13.1, .z = 21.0 });
                }

                {
                    const zone = ztracy.ZoneNS(@src(), "Set component rotation", 10);
                    defer zone.End();
                    try game.set(player1, .rotation, .{ .degrees = 90 });
                }

                {
                    const zone = ztracy.ZoneNS(@src(), "Set component monster", 10);
                    defer zone.End();
                    try game.set(player1, .is_monster, {});
                }
            }
            const t: f32 = @floatFromInt(std.time.microTimestamp() - t_start);
            std.debug.print("Time per creation {d:.1} us total {d:.1} \n", .{ t / N, t });
        }
    }

    for (0..12) |_| {
        try queryFunction(entities);

        try queryFunction2(entities);
    }
}
