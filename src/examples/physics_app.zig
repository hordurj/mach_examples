//! An example to test mach.math.collsion.

const std = @import("std");
const mach = @import("mach");
const math = mach.math;
const vec2 = math.vec2;
const Vec2 = math.Vec2;
const mat2x2 = math.mat2x2;
const Mat2x2 = math.Mat2x2;
const vec3 = math.vec3;
const Vec3 = math.Vec3;
const vec4 = math.vec4;
const Vec4 = math.Vec4;
const Mat4x4 = math.Mat4x4;
const collision = math.collision;

const gpu = mach.gpu;
const gm = @import("../geometry.zig");
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

// TODO
//   think about how to sync shared state, e.g. position between shape and body
//   change shape to a tagged union?   or support querying any of (circle, rectangle, ...)
//   improve integration method
//   ECS helpers, copy, copy fields, remove, visit, ...
//

// App state
world: World,

// Resources
allocator: std.mem.Allocator,
frame_encoder: *gpu.CommandEncoder = undefined,
frame_render_pass: *gpu.RenderPassEncoder = undefined,
shapes_canvas: mach.EntityID = undefined,
prng: std.Random.DefaultPrng,
rand: std.Random,

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
    .physics_body = .{ .type = Body },      // Tag physics bodies
    .position = . { .type = Vec2 },
    .velocity = .{ .type = Vec2 },
    .friction = .{ .type = f32 },
    .orientation = .{ .type = f32 },         // Angle
    //    .elasticity
    .invmass = .{ .type = f32 },

    // Collision
    .collider = . { .type = Collider },    
};

fn rotate(a: f32) Mat2x2 {
    const c = math.cos(a);
    const s = math.sin(a);
    return mat2x2(
        vec2(c, -s),
        vec2(s, c),
    );
}

fn perp(v: Vec2) Vec2 {
    return vec2(-v.y(), v.x());
}
// Physics body
//   a physics body consits of 
//      position
//      orientation
//      center_of_mass   - cg
//      shape
//      
const Body = struct {
    position: Vec2,
    velocity: Vec2,
    angular_velocity: f32,
    orientation: f32, 
    inv_mass: f32,
    elasticity: f32 = 1.0,
    friction: f32 = 0.0,
    inv_inertia: f32,
    // center of mass

    fn center_of_mass_world(self: *Body) Vec2 {
//        return rotate(orienation).mulVec(&self.position)
        return self.position;   // just implementing for circle/disk for now
    }

    fn applyImpulse(self: *Body, impulse_point: Vec2, impulse: Vec2) void {
        if (self.inv_mass == 0.0) {
            return;
        }

        self.applyImpulseLinear(impulse);

        const pos = self.center_of_mass_world();
        const r = impulse_point.sub(&pos);
        const dL = gm.cross2d(r, impulse); 

        self.applyImpulseAngular(dL);
    }

    fn applyImpulseLinear(self: *Body, impulse: Vec2) void {
        if (self.inv_mass == 0.0) {
            return;
        }

        self.velocity = self.velocity.add(&impulse.mulScalar(self.inv_mass));
    }

    fn applyImpulseAngular(self: *Body, impulse: f32) void {
        if (self.inv_mass == 0.0) {
            return;
        }
        self.angular_velocity += self.inv_inertia * impulse;
        //std.debug.print("Angular velocity: {} {} {}\n", .{self.angular_velocity, self.inv_inertia, impulse});
        const max_angular_velocity = 30.0;
        if (self.angular_velocity > max_angular_velocity) {
            self.angular_velocity = max_angular_velocity;
        }
    }

    fn update(self: *Body, dt: f32) void {
        self.position = self.position.add(&self.velocity.mulScalar(dt));
        self.orientation += self.angular_velocity * dt;
    }
};

const Contact = struct {
    pt_on_a_world: Vec2,
    pt_on_b_world: Vec2,
    pt_on_a_local: Vec2 = undefined,
    pt_on_b_local: Vec2 = undefined,
    normal: Vec2,
    distance: f32  = undefined,
    time_of_impact: f32  = undefined,
    body_a: *Body,
    body_b: *Body
};

// Manage a 
const World = struct {
    dt: f32 = 1.0 / 60.0,               // Timestep
    sub_steps: u32 = 1,                 // Number of sub steps to perform per update
    gravity: Vec2 = vec2(0.0, -9.8),    

    fn update(self: *World, entities: *mach.Entities.Mod) !void {
        var q = try entities.query(.{
            .ids = mach.Entities.Mod.read(.id),
            .bodies = Mod.write(.physics_body),
            .shapes = shp.Mod.read(.circle),             // Probably easier to have a generic shape 
            // shape
        });
        while (q.next()) |v| {
            for (v.ids, v.bodies, v.shapes) |id, *body, shape| {
                // _ = id;
                if (body.inv_mass == 0.0) {
                    // Heavy objects are not moved by physics
                    continue ;                    
                }

                const mass = 1.0 / body.inv_mass;
                const impulse_gravity = self.gravity.mulScalar(mass * self.dt);
                body.applyImpulseLinear(impulse_gravity);

                // Check for collision
                //if (try World.checkCollision(id, body, shape, entities)) {
                //    body.velocity = vec2(0.0, 0.0);
                //}
                // _ = shape;

                var q2 = try entities.query(.{
                    .ids = mach.Entities.Mod.read(.id),
                    .bodies = Mod.write(.physics_body),
                    .shapes = shp.Mod.read(.circle),
                });
                const collider_a = collision.Circle{.pos = body.position, .radius = shape.size.x()/2.0};

                while (q2.next()) |v2| {
                    for (v2.ids, v2.bodies, v2.shapes) |id_b, *body_b, shape_b| {
                        if (id == id_b) {
                            continue ;
                        }
                        const collider_b = collision.Circle{.pos = body_b.position, .radius = shape_b.size.x()/2.0};
                        if (collider_b.collidesCircle(collider_a)) {
                            const radius_a = shape.size.x() / 2.0;
                            const radius_b = shape_b.size.x() / 2.0;

                            const normal = body_b.position.sub(&body.position).normalize(0.0);

                            const contact = Contact{
                                .body_a = body,
                                .body_b = body_b,
                                .pt_on_a_world = body.position.add(&normal.mulScalar(radius_a)),
                                .pt_on_b_world = body_b.position.sub(&normal.mulScalar(radius_b)),
                                .normal = normal,
                            };

                            //std.debug.print("Collision id {} {} pos {} {} radius {d} {d} \n", .{id, id_b, collider_a.pos, collider_b.pos, collider_a.radius, collider_b.radius});
                            try World.resolveContact(&contact);
                        } 
                    }
                }

                body.update(self.dt);
            }
        }
    }

    fn resolveContact(contact: *const Contact) !void 
    {
        const body_a = contact.body_a;
        const body_b = contact.body_b;
        const elasticity = body_a.elasticity * body_b.elasticity; // Or choose max.
        const n = contact.normal;

        const ra = contact.pt_on_a_world.sub(&body_a.position);
        const rb = contact.pt_on_a_world.sub(&body_b.position);
        
        const angular_J_a = perp(ra).mulScalar(gm.cross2d(ra, n)).mulScalar(body_a.inv_inertia);
        const angular_J_b = perp(rb).mulScalar(gm.cross2d(rb, n)).mulScalar(body_b.inv_inertia);
        const angular_factor = angular_J_a.add(&angular_J_b).dot(&n);

        const inv_mass_ab = body_a.inv_mass + body_b.inv_mass;

        // Collision impulse
        const vel_a = body_a.velocity.add(&perp(ra).mulScalar(body_a.angular_velocity));
        const vel_b = body_b.velocity.add(&perp(rb).mulScalar(body_b.angular_velocity));
        const vab = vel_a.sub(&vel_b);
        const impulse_j = -(1.0 + elasticity) * vab.dot(&n) / (inv_mass_ab + angular_factor);

        body_a.applyImpulse(contact.pt_on_a_world, n.mulScalar(impulse_j));
        body_b.applyImpulse(contact.pt_on_b_world, n.mulScalar(-impulse_j));

        // Friction impulse
        const friction = body_a.friction + body_b.friction;
        const vel_normal = n.mulScalar(n.dot(&vab));
        const vel_tang = vab.sub(&vel_normal);
        const relative_vel_tang = vel_tang.normalize(0.0);
        const inv_inertia_a = perp(ra).mulScalar(gm.cross2d(ra, relative_vel_tang)).mulScalar(body_a.inv_inertia);
        const inv_inertia_b = perp(rb).mulScalar(gm.cross2d(rb, relative_vel_tang)).mulScalar(body_b.inv_inertia);
        const inv_inertia = inv_inertia_a.add(&inv_inertia_b).dot(&relative_vel_tang);
        const reduced_mass = 1.0 / (inv_mass_ab + inv_inertia);

        body_a.applyImpulse(contact.pt_on_a_world, vel_tang.mulScalar(-friction*reduced_mass));
        body_b.applyImpulse(contact.pt_on_b_world, vel_tang.mulScalar(friction*reduced_mass));

        // Move object apart
        const t_a = body_a.inv_mass / inv_mass_ab;
        const t_b = body_b.inv_mass / inv_mass_ab;
        const d = contact.pt_on_b_world.sub(&contact.pt_on_a_world);
        body_a.position = body_a.position.add(&d.mulScalar(t_a));        
        body_b.position = body_b.position.sub(&d.mulScalar(t_b));        
    }

    fn checkCollision(id_a: mach.EntityID, body_a: *const Body, shape_a: shp.Circle, entities: *mach.Entities.Mod) !bool {
//        _ = self;self: *World, 
        var q = try entities.query(.{
            .ids = mach.Entities.Mod.read(.id),
            .bodies = Mod.read(.physics_body),
            .shapes = shp.Mod.read(.circle),
        });
        const collider_a = collision.Circle{.pos = body_a.position, .radius = shape_a.size.x()};

        while (q.next()) |v| {
            for (v.ids, v.bodies, v.shapes) |id_b, body_b, shape_b| {
                if (id_a == id_b) {
                    continue ;
                }
                const collider_b = collision.Circle{.pos = body_b.position, .radius = shape_b.size.x()};
                if (collider_b.collidesCircle(collider_a)) {
                    return false;
                } 
            }
        }

        return false;
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

fn box_sdf(p: Vec2, x: f32, y: f32, w: f32, h: f32) f32 {
    const dx = @max(@abs(p.x() - x - w/2) - w/2, 0.0);
    const dy = @max(@abs(p.y() - y - h/2) - h/2, 0.0);
    return @sqrt(dx*dx + dy*dy);
}

// ---------------------
//  Internal functions
// ---------------------
fn setupWorld( self: *Mod,
    core: *mach.Core.Mod,
    entities: *mach.Entities.Mod,
    shapes: *shp.Mod,
) !void {
//    const width: f32 = @floatFromInt(core.get(core.state().main_window, .width).?);
    const height: f32 = @floatFromInt(core.get(core.state().main_window, .height).?);

    var canvas = Canvas{
        .entities=entities, 
        .shapes=shapes, 
        .canvas=self.state().shapes_canvas,
        .line_style = .{.color =  col(.DarkGrey), .width = 5.0},
        .fill_style = .{.color =  col(.MidnightBlue)},
    };    

    // Create ground
    const radius = 10000.0;
    const physics_body = Body{
        .position = vec2(0.0, -height/2 + 50.0 - 10000.0),
        .velocity = vec2(0.0, 0.0),
        .orientation = 0.0,
        .angular_velocity = 0.0,
        .inv_mass = 0.0,
        .inv_inertia = 0.0,
        .friction = 0.5,
    };
    const ground = try createCircle(self, &canvas, physics_body.position, radius);        
    try self.set(ground, .physics_body, physics_body);
}

fn setupWorld2( self: *Mod,
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
        .world = World{.gravity = vec2(0.0, -98.0)},
        .prng = std.rand.DefaultPrng.init(13127),
        .rand = undefined
    });
    self.state().rand = self.state().prng.random();

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

                if (ev.button == .left) {
                    const radius: f32 = self.state().rand.float(f32) * 20.0 + 10.0;//  = 10.0;
                    const inv_mass = 1.0 / radius / radius; //1.0; //1.0;
                    const ball_body = Body{
                        .position = vec2(x, y),
                        .velocity = vec2(0.0, 0.0),
                        .orientation = 0.0,
                        .angular_velocity = 0.0,
                        .elasticity = 0.8,
                        .inv_mass = inv_mass,
                        .inv_inertia = 2.0 * inv_mass / radius / radius,
                        .friction = 0.5,
                    };
                    const ball = try shp.drawCircle(&canvas, ball_body.position.x(), ball_body.position.y(), radius * 2.0, radius * 2.0);
                    try self.set(ball, .physics_body, ball_body);
                    try self.set(ball, .velocity, vec2(2.0, 0.0));
                } else if (ev.button == .right) {
                    const w: f32 = self.state().rand.float(f32) * 40.0 + 20.0;
                    const h: f32 = self.state().rand.float(f32) * 40.0 + 20.0;
                    const inv_mass = 1.0 / w / h; 
                    const box_body = Body{
                        .position = vec2(x, y),
                        .velocity = vec2(0.0, 0.0),
                        .orientation = 0.0,
                        .angular_velocity = 0.0,
                        .elasticity = 0.8,
                        .inv_mass = inv_mass,
                        .inv_inertia = 12.0 * inv_mass / (w*w + h*h),
                        .friction = 0.5,
                    };
                    const box = try shp.drawRect(&canvas, box_body.position.x(), box_body.position.y(), w, h);
                    try self.set(box, .physics_body, box_body);
                    try self.set(box, .velocity, vec2(2.0, 0.0));
                }
            },
            .mouse_release => |ev| {
                _ = ev;

            },
            .close => core.schedule(.exit),
            else => {},
        }
    }
}

fn tick_move(
    self: *Mod, 
    core: *mach.Core.Mod,
    entities: *mach.Entities.Mod,
    shapes: *shp.Mod
) !void {
    _ = core;
    _ = shapes;

    try self.state().world.update(entities);
    var q = try entities.query(.{
        .bodies = Mod.read(.physics_body),
        .shapes = shp.Mod.write(.circle),
        .transforms = shp.Mod.write(.transform)
    });
    while (q.next()) |v| {
        for (v.bodies, v.shapes, v.transforms) |body, *shape, *transform| {
            shape.center = body.position;
            transform.* = Mat4x4.rotateZ(body.orientation);
            //std.debug.print("Orientation {d:.2} {d:.2}\n", .{math.radiansToDegrees(body.orientation), math.radiansToDegrees(body.angular_velocity)});
        }
    }
}

fn tick_move_2(
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
