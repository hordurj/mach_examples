const std = @import("std");
const mach = @import("mach");
const math = mach.math;
const vec2 = math.vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Vec4 = math.Vec4;
const Mat4x4 = math.Mat4x4;
const gpu = mach.gpu;
const ex_shapes = @import("../shapes/main.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// App state
width: f32 = 960.0,         // Width of render area - will be scaled to window
height: f32 = 540.0,        // Height of render area - will be scaled to window

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
    .tick = .{ .handler = tick },
    .input = .{ .handler = tick_input },
    .move = .{ .handler = tick_move },
    .render = .{ .handler = tick_render },
    .end_frame = .{ .handler = endFrame },
};

pub const components = .{
    .velocity = .{ .type = math.Vec2, .description = ""},
};

fn init(
    self: *Mod,
    core: *mach.Core.Mod,
    shapes: *ex_shapes.Mod,
) !void {
    core.schedule(.init);
    shapes.schedule(.init);
    self.schedule(.after_init);    
}
fn deinit(
    self: *Mod,
    core: *mach.Core.Mod,
    shapes: *ex_shapes.Mod,
) !void {
    _ = self;
    shapes.schedule(.deinit);
    core.schedule(.deinit);
}

fn afterInit(
    self: *Mod,
    core: *mach.Core.Mod,
    entities: *mach.Entities.Mod,
    shapes: *ex_shapes.Mod,
) !void {
    const allocator = gpa.allocator();

    const shapes_canvas = try entities.new();
    try  shapes.set(shapes_canvas, .shapes_pipeline, {});
    shapes.schedule(.update);

    self.init(.{
        .allocator = allocator,
        .shapes_canvas = shapes_canvas,
    });

    const rect1 = try entities.new();
    try shapes.set(rect1, .pipeline, shapes_canvas); 
    try shapes.set(rect1, .transform, Mat4x4.translate(vec3(0.0, 0.0, 0.0)));
    try shapes.set(rect1, .color, vec4(0.5, 0.2, 0.1, 1.0));
    try shapes.set(rect1, .rectangle, 
        .{ 
            .center = vec2(0.0, 0.0),
            .size = vec2(100.0, 50.0)
        }
    );

    const rect2 = try entities.new();
    try shapes.set(rect2, .pipeline, shapes_canvas); 
    try shapes.set(rect2, .transform, Mat4x4.translate(vec3(0.0, 0.0, 0.0)));
    try shapes.set(rect2, .color, vec4(0.1, 0.2, 0.9, 1.0));
    try shapes.set(rect2, .rectangle, 
        .{ 
            .center = vec2(200.0, 200.0),
            .size = vec2(50.0, 50.0)
        }
    );

    const circle1 = try entities.new();
    try shapes.set(circle1, .pipeline, shapes_canvas); 
    try shapes.set(circle1, .transform, Mat4x4.translate(vec3(0.0, 0.0, 0.0)));
    try shapes.set(circle1, .color, vec4(0.1, 0.9, 0.3, 1.0));
    try shapes.set(circle1, .circle, 
        .{ 
            .center = vec2(-200.0, -200.0),
            .size = vec2(50.0, 50.0)
        }
    );

    const circle2 = try entities.new();
    try shapes.set(circle2, .pipeline, shapes_canvas); 
    try shapes.set(circle2, .transform, Mat4x4.translate(vec3(0.0, 0.0, 0.0)));
    try shapes.set(circle2, .color, vec4(0.5, 0.9, 0.3, 1.0));
    try shapes.set(circle2, .circle, 
        .{ 
            .center = vec2(200.0, -200.0),
            .size = vec2(50.0, 50.0)
        }
    );

    _ = try ex_shapes.drawCircle(entities, shapes, shapes_canvas, 100.0, 100.0, 20.0, 20.0, vec4(1.0, 0.0, 0.0, 1.0));
    _ = try ex_shapes.drawCircle(entities, shapes, shapes_canvas, 140.0, 100.0, 20.0, 20.0, vec4(0.0, 1.0, 0.0, 1.0));
    _ = try ex_shapes.drawCircle(entities, shapes, shapes_canvas, 130.0, -200.0, 20.0, 20.0, vec4(0.0, 0.0, 1.0, 1.0));

    _ = try ex_shapes.drawRect(entities, shapes, shapes_canvas, -100.0, 200.0, 20.0, 20.0, vec4(1.0, 0.0, 0.0, 1.0));
    _ = try ex_shapes.drawRect(entities, shapes, shapes_canvas, -140.0, 100.0, 20.0, 20.0, vec4(0.0, 1.0, 0.0, 1.0));
    _ = try ex_shapes.drawRect(entities, shapes, shapes_canvas, -130.0, -200.0, 20.0, 20.0, vec4(0.0, 0.0, 1.0, 1.0));

    _ = try ex_shapes.drawLine(entities, shapes, shapes_canvas, 100.0, 200.0, 220.0, 320.0, 10.0, vec4(1.0, 0.0, 0.0, 1.0));
    _ = try ex_shapes.drawLine(entities, shapes, shapes_canvas, 140.0, -100.0, 120.0, 420.0, 5.0,  vec4(0.0, 1.0, 0.0, 1.0));
    _ = try ex_shapes.drawLine(entities, shapes, shapes_canvas, 130.0, 200.0, -220.0, -220.0, 1.0, vec4(0.0, 0.0, 1.0, 1.0));


    _ = try ex_shapes.drawLine(entities, shapes, shapes_canvas, -100.0, -100.0, 300.0, -100.0, 5.0, vec4(1.0, 1.0, 1.0, 1.0));
    _ = try ex_shapes.drawLine(entities, shapes, shapes_canvas, 300.0, -100.0, 300.0,  100.0, 5.0,  vec4(1.0, 1.0, 1.0, 1.0));
    _ = try ex_shapes.drawLine(entities, shapes, shapes_canvas, 300.0, 100.0, -100.0, 100.0, 5.0, vec4(1.0, 1.0, 1.0, 1.0));
    _ = try ex_shapes.drawLine(entities, shapes, shapes_canvas, -100.0, 100.0, -100.0, -100.0, 5.0, vec4(1.0, 1.0, 1.0, 1.0));

    shapes.schedule(.update_shapes);

    core.schedule(.start);
}

fn tick(
    self: *Mod,
) !void {
    self.schedule(.input);
    self.schedule(.move);
    self.schedule(.render);
}

fn tick_input(
    self: *Mod, 
    core: *mach.Core.Mod,
    entities: *mach.Entities.Mod,
    shapes: *ex_shapes.Mod
) !void {    
    const shapes_canvas = self.state().shapes_canvas;
    var iter = mach.core.pollEvents();
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
                var x: f32 = @floatCast(ev.pos.x); x -= self.state().width / 2.0;
                var y: f32 = @floatCast(ev.pos.y); y = -y + self.state().height / 2.0;

                std.debug.print("Add ball {} {}\n", .{x, y});

                const ball = try ex_shapes.drawCircle(entities, shapes, shapes_canvas, x, y, 10.0, 10.0, vec4(1.0, 1.0, 1.0, 1.0));
                try self.set(ball, .velocity, vec2(2.0, 0.0));
                shapes.schedule(.update_shapes);
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
    shapes: *ex_shapes.Mod
) !void {
    _ = core;
    const width = self.state().width;
    const height = self.state().height;

    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .circles = ex_shapes.Mod.write(.circle),
        .velocity = Mod.write(.velocity),
    });
    while (q.next()) |v| {
        for (v.ids, v.circles, v.velocity) |obj_id, *circle, *velocity| {
            _ = obj_id;
            if (circle.*.center.v[0] < -width/2.0) {
                velocity.*.v[0] *= -1.0;
                circle.*.center.v[0] = -width/2.0;
            }
            if (circle.*.center.v[0] > width/2.0) {
                velocity.*.v[0] *= -1.0;
                circle.*.center.v[0] = width/2.0;
            }
            if (circle.*.center.v[1] < -height/2.0) {
                velocity.*.v[1] *= -1.0;
                circle.*.center.v[1] = -height/2.0;
            }
            if (circle.*.center.v[1] > height/2.0) {
                velocity.*.v[1] *= -1.0;
                circle.*.center.v[1] = height/2.0;
            }

            circle.*.center.v[0] += velocity.*.v[0];
            circle.*.center.v[1] += velocity.*.v[1];

            // Gravity
            velocity.*.v[1] -= 9.8/120.0;

        }
    }

    shapes.schedule(.update_shapes);
}

fn tick_render(
    self: *Mod,
    core: *mach.Core.Mod,
    shapes: *ex_shapes.Mod,
) !void {

    const label = @tagName(name) ++ ".render";
    self.state().frame_encoder = core.state().device.createCommandEncoder(&.{ .label = label });

    const back_buffer_view = mach.core.swap_chain.getCurrentTextureView().?;
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

    core.schedule(.update);
    core.schedule(.present_frame);
}
