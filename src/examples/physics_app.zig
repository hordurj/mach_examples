//! An example to test mach.math.collsion.

const std = @import("std");
const mach = @import("mach");
const math = mach.math;
const vec2 = math.vec2;
const Vec2 = math.Vec2;
const vec3 = math.vec3;
const Vec3 = math.Vec3;
const vec4 = math.vec4;
const Vec4 = math.Vec4;
const Mat4x4 = math.Mat4x4;
const collision = math.collision;

const gpu = mach.gpu;
const shp = @import("../shapes/main.zig");
const Canvas = shp.Canvas;
const LineStyle = shp.LineStyle;
const FillStyle = shp.FillStyle;
const drawCircle = shp.drawCircle;
const drawLine = shp.drawLine;
const drawRect = shp.drawRect;
const col = shp.col;
const rgb = shp.rgb;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// App state

// Resources
allocator: std.mem.Allocator,
frame_encoder: *gpu.CommandEncoder = undefined,
frame_render_pass: *gpu.RenderPassEncoder = undefined,
shapes_canvas: mach.EntityID = undefined,

pub const name = .app; // The main app has to be named .app
pub const Mod = mach.Mod(@This());

pub const systems = .{
    .init = .{ .handler = init },
    .deinit = .{ .handler = deinit },
    .after_init = .{ .handler = afterInit },
    .update = .{ .handler = update },
    .input = .{ .handler = tick_input },
    .move = .{ .handler = tick_move },
    .render = .{ .handler = tick_render },
    .end_frame = .{ .handler = endFrame },
};

const ColliderType = enum {
    rectangle,
    circle,
    point,
//    triangle,
//    polygon,
    line
};
const Collider = union(ColliderType) {
    rectangle: collision.Rectangle,
    circle: collision.Circle,
    point: collision.Point,
//    triangle: []Vec2,
//    polygon: []Vec2
    line: collision.Line
};

pub const components = .{
    // Physics
    .physics_body = .{ .type = void },      // Tag physics bodies
    .position = . { .type = Vec2 },
    .velocity = .{ .type = Vec2 },
    .friction = .{ .type = f32 },
    .orientation = .{ .type = f32 },         // Angle
    //    .elasticity
    .invmass = .{ .type = f32 },

    // Collision
    .collider = . { .type = Collider },

    
};

// Physics body
//   a physics body consits of 
//      position
//      orientation
//      center_of_mass   - cg
//      shape
//      

// Manage a 
const World = struct {
    dt: f32 = 1.0 / 60.0,               // Timestep
    sub_steps: u32 = 1,                 // Number of sub steps to perform per update
    gravity: Vec2 = vec2(0.0, -9.8),    

    fn update(self: *World, entities: *mach.Entities.Mod) !void {
        _ = self;

    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .physics_body = Mod.Mod.read(.physics_body),
        .positions = Mod.write(.position),
        .orientations = Mod.write(.orientation),
        .velocities = Mod.write(.velocity),
    });
    while (q.next()) |v| {
        for (v.ids, v.position, v.velocities) |id, pos, vel| {
            _ = id;
            _ = pos;
            _ = vel;
            // update velocities
            // update positions
        }
    }

    }
};

fn createRectangle(self: *Mod, canvas: *Canvas, pos: Vec2, size: Vec2) !mach.EntityID {
    const rect = try drawRect(canvas, 
        pos.x() + size.x()/2.0,
        pos.y() + size.y()/2.0, 
        size.x(), 
        size.y());
    try self.set(rect, .collider, .{
        .rectangle = .{ .pos = pos, .size = size }});
    try self.set(rect, .friction, 0.0);
    try self.set(rect, .invmass, 0.0);
    return rect;
}

fn createCircle(self: *Mod, canvas: *Canvas, pos: Vec2, radius: f32) !mach.EntityID {
    const circle = try drawCircle(canvas, 
        pos.x(),
        pos.y(), 
        2.0 * radius, 
        2.0 * radius);
    try self.set(circle, .collider, .{
        .circle = .{ .pos = pos, .radius = radius }});
    try self.set(circle, .friction, 0.0);
    try self.set(circle, .invmass, 0.0);
    return circle;
}

// ---------------------
//  Internal functions
// ---------------------
fn setupWorld( self: *Mod,
    core: *mach.Core.Mod,
    entities: *mach.Entities.Mod,
    shapes: *shp.Mod,
) !void {
    const width: f32 = @floatFromInt(core.get(core.state().main_window, .width).?);
    const height: f32 = @floatFromInt(core.get(core.state().main_window, .height).?);

    // Add walls
    var canvas = Canvas{
        .entities=entities, 
        .shapes=shapes, 
        .canvas=self.state().shapes_canvas,
        .line_style = .{.color =  col(.DarkGrey), .width = 5.0},
        .fill_style = .{.color =  col(.MidnightBlue)},
    };

    canvas.fill_style.color = col(.White);
    _ = try createRectangle(self, &canvas, vec2(-width/2.0, -height/2.0), vec2(10.0, height));
    _ = try createRectangle(self, &canvas, vec2(width/2.0 - 10.0, -height/2.0), vec2(10.0, height));
    _ = try createRectangle(self, &canvas, vec2(-width/2.0, -height/2.0), vec2(width, 10.0));
    _ = try createRectangle(self, &canvas, vec2(-width/2.0, height/2.0-10.0), vec2(width, 10.0));

    var prng = std.rand.DefaultPrng.init(13127);
    const rand = prng.random();

    // Add circle obstacles

    canvas.fill_style.color = col(.Blue);
    for (0..10) |_| {
        const pos = vec2( (rand.float(f32)-0.5) * width, (rand.float(f32)-0.5) * height);
        const radius = rand.float(f32) * 20 + 10.0;

        // Choose random color
        _ = try createCircle(self, &canvas, pos, radius);        
    }

    // Add rectangle obstacles
    canvas.fill_style.color = col(.Red);
    for (0..10) |_| {
        const pos = vec2( (rand.float(f32)-0.5) * width, (rand.float(f32)-0.5) * height);
        const size = vec2(rand.float(f32) * 100.0+20, rand.float(f32) * 50.0 + 10.0);

        // Choose random color
        _ = try createRectangle(self, &canvas, pos, size);
    }

    // Add triangle obstacles

    // Add line obstacles

}
// --------------------
//  Systems
// --------------------
fn init(
    self: *Mod,
    core: *mach.Core.Mod,
    shapes: *shp.Mod,
) !void {
    _ = core;
//    core.schedule(.init, .{});
    shapes.schedule(.init);
    self.schedule(.after_init);    
}
fn deinit(
    shapes: *shp.Mod,
) !void {
    shapes.schedule(.deinit);
}

fn afterInit(
    self: *Mod,
    core: *mach.Core.Mod,
    entities: *mach.Entities.Mod,
    shapes: *shp.Mod,
) !void {
    const allocator = gpa.allocator();

    const shapes_canvas = try entities.new();
    try  shapes.set(shapes_canvas, .shapes_pipeline, {});
    try  shapes.set(shapes_canvas, .pipeline, shapes_canvas);
    shapes.schedule(.update);

    self.init(.{
        .allocator = allocator,
        .shapes_canvas = shapes_canvas,
    });

    try setupWorld(self, core, entities, shapes);

    shapes.schedule(.update_shapes);
}

fn update(
    core: *mach.Core.Mod,
    self: *Mod,
) !void {
    if (core.state().should_close) {
        return;
    }

    self.schedule(.input);
    self.schedule(.move);
    self.schedule(.render);
}

fn tick_input(
    self: *Mod, 
    core: *mach.Core.Mod,
    entities: *mach.Entities.Mod,
    shapes: *shp.Mod
) !void {    
    const shapes_canvas = self.state().shapes_canvas;
    var iter = core.state().pollEvents();
    // Handle inputs
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .escape, .q => core.schedule(.exit),
                    else => {},
                }
            },
            .mouse_press => |ev| {
                // TODO: need a screen to world transformation
                const window = core.state().main_window;
                const width:f32 = @floatFromInt(core.get(window, .width).?);
                const height:f32 = @floatFromInt(core.get(window, .height).?);
                var x: f32 = @floatCast(ev.pos.x); x -= width / 2.0;
                var y: f32 = @floatCast(ev.pos.y); y = -y + height / 2.0;

                var canvas = Canvas{
                    .entities=entities, 
                    .shapes=shapes, 
                    .canvas=shapes_canvas,
                    .line_style = .{.color =  col(.MediumSlateBlue), .width = 2.0},
                    .fill_style = .{.color =  col(.SkyBlue)},
                };
                const ball = try shp.drawCircle(&canvas, x, y, 20.0, 20.0);
                try self.set(ball, .velocity, vec2(2.0, 0.0));
                // add collider
            },
            .mouse_release => |ev| {
                _ = ev;

            },
            .close => core.schedule(.exit),
            else => {},
        }
    }
}

fn box_sdf(p: Vec2, x: f32, y: f32, w: f32, h: f32) f32 {
    const dx = @max(@abs(p.x() - x - w/2) - w/2, 0.0);
    const dy = @max(@abs(p.y() - y - h/2) - h/2, 0.0);
    return @sqrt(dx*dx + dy*dy);
}

fn tick_move(
    self: *Mod, 
    core: *mach.Core.Mod,
    entities: *mach.Entities.Mod,
    shapes: *shp.Mod
) !void {
    _ = self;
    _ = core;
    //const width: f32 = @floatFromInt(core.get(core.state().main_window, .width).?);
    //const height: f32 = @floatFromInt(core.get(core.state().main_window, .height).?);

    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .circles = shp.Mod.write(.circle),
        .velocity = Mod.write(.velocity),
    });
    while (q.next()) |v| {
        for (v.ids, v.circles, v.velocity) |obj_id, *circle, *velocity| {
            // Gravity
            velocity.*.v[1] -= 9.8/120.0;

            circle.*.center = circle.*.center.add(velocity); 

            var collisions = try entities.query(.{
                .ids = mach.Entities.Mod.read(.id),
                .colliders = Mod.read(.collider),
                .invmasss = Mod.read(.invmass),
            });
            while (collisions.next()) |cols| {
                for (cols.ids, cols.colliders, cols.invmasss) |id, collider, invmass| {
                    _ = invmass;
                    if (obj_id != id) { 
                        switch (collider) {
                            .rectangle => |r| {
                                const pos = circle.*.center;
                                const radius = circle.*.size.x() / 2.0;
                                const vel = velocity.*;
                                const circle_collider = collision.Circle{.pos = circle.*.center, .radius = radius};
                                if (circle_collider.collidesRect(r)) {
                                    // TODO find which side it collides with
                                    
                                    const d_left = box_sdf(pos, r.pos.x(), r.pos.y(), 0, r.size.y());
                                    const d_right = box_sdf(pos, r.pos.x()+r.size.x(), r.pos.y(), 0, r.size.y());
                                    const d_top = box_sdf(pos, r.pos.x(), r.pos.y(), r.size.x(), 0);
                                    const d_bottom = box_sdf(pos, r.pos.x(), r.pos.y()+r.size.y(), r.size.x(), 0);
                                    var t: f32 = 0.0;

                                    var new_n: Vec2 = undefined;
                                    const distances = [_]f32{d_left,d_right,d_top,d_bottom};
                                    const normals = [_]Vec2{
                                        vec2(-1.0, 0.0),
                                        vec2(1.0, 0.0),
                                        vec2(0.0, -1.0),
                                        vec2(0.0, 1.0)};

                                    for (distances, normals) |d, n| {
                                        // Check if intersects and moving towards side
                                        if (d < radius and vel.dot(&n) < 0) {
                                            const t_n = @abs((radius - d) / vel.dot(&n));
                                            if (t_n > t) {
                                                t = t_n;
                                                new_n = n;
                                            } else if (t_n == t) {
                                                new_n = n.add(&new_n).normalize(0.0);
                                            }
                                        }
                                    }
                                    if (t > 0.0) {
                                        // obj.pos = obj.last_pos + (dt - t) * obj.vel
                                        // obj.vel = obj.vel - 2.0 * obj.vel.dot(new_n) * new_n
                                        // obj.pos = obj.pos + t * obj.vel
                                        
                                        // todo handle last pos, and t for time of intersection

                                        const v_dot_n = new_n.mulScalar(2.0 * vel.dot(&new_n));
                                        velocity.* = vel.sub(&v_dot_n);

                                        // Adjust pos to be outside
                                        circle.*.center = circle.*.center.add(&new_n.mulScalar(t));
                                    }                        
                                }
                            },
                            .circle => |c| {
                                const pos = circle.*.center;
                                const radius = circle.*.size.x() / 2.0;
                                const vel = velocity.*;
                                const circle_collider = collision.Circle{.pos = pos, .radius = radius};

                                if (circle_collider.collidesCircle(c)) {
                                    const d = c.pos.sub(&pos); 
                                    var new_n: Vec2 = d.normalize(0.0);
                                    const v_dot_n = new_n.mulScalar(2.0 * vel.dot(&new_n));
                                    velocity.* = vel.sub(&v_dot_n);

                                    // Adjust pos to be outside
                                    circle.*.center = circle.*.center.add(&new_n.mulScalar(d.len() - radius - c.radius));
                                }
                            },
                            else => {
                                std.debug.print("Do not know how to collide with {}\n", .{collider});
                            }
                        }
                    }
                }
            }
        }
    }

    shapes.schedule(.update_shapes);
}

fn tick_render(
    self: *Mod,
    core: *mach.Core.Mod,
    shapes: *shp.Mod,
) !void {

    const label = @tagName(name) ++ ".render";
    self.state().frame_encoder = core.state().device.createCommandEncoder(&.{ .label = label });

    const back_buffer_view = core.state().swap_chain.getCurrentTextureView().?;
    defer back_buffer_view.release();

    // Begin render pass
    const color_attachments = [_]gpu.RenderPassColorAttachment{.{
        .view = back_buffer_view,
        .clear_value = gpu.Color{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        .load_op = .clear,
        .store_op = .store,
    }};
    self.state().frame_render_pass = self.state().frame_encoder.beginRenderPass(&gpu.RenderPassDescriptor.init(.{
        .label = label,
        .color_attachments = &color_attachments,
    }));

    // Shapes
    shapes.state().render_pass = self.state().frame_render_pass;
    shapes.schedule(.update_shapes);        // Only happens is shapes have changed
    shapes.schedule(.pre_render);           
    shapes.schedule(.render);

    // Finish the frame once rendering is done.
    self.schedule(.end_frame);
}

fn endFrame(
    self: *Mod, 
    core: *mach.Core.Mod
) !void {
    // Finish render pass
    self.state().frame_render_pass.end();
    const label = @tagName(name) ++ ".endFrame";
    var command = self.state().frame_encoder.finish(&.{ .label = label });
    core.state().queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    self.state().frame_encoder.release();
    self.state().frame_render_pass.release();

    core.schedule(.present_frame);


    // Every second, update the window title with the FPS
    try core.state().printTitle(
        core.state().main_window,
        "Physics [ {d}fps ] [ Input {d}hz ]",
        .{
            // TODO(Core)
            core.state().frameRate(),
            core.state().inputRate(),
        },
    );

}
