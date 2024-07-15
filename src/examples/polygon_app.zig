const std = @import("std");
const mach = @import("mach");
const math = mach.math;
const vec2 = math.vec2;
const Vec2 = math.Vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Vec4 = math.Vec4;
const Mat4x4 = math.Mat4x4;
const gpu = mach.gpu;
const ex_shapes = @import("../shapes/main.zig");
const Canvas = ex_shapes.Canvas;
const LineStyle = ex_shapes.LineStyle;
const FillStyle = ex_shapes.FillStyle;
const drawCircle = ex_shapes.drawCircle;
const drawLine = ex_shapes.drawLine;
const drawRect = ex_shapes.drawRect;
const drawTriangle = ex_shapes.drawTriangle;
const col = ex_shapes.col;
const rgb = ex_shapes.rgb;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// App state
width: f32 = 960.0,         // Width of render area - will be scaled to window
height: f32 = 540.0,        // Height of render area - will be scaled to window

// Resources
allocator: std.mem.Allocator,
frame_encoder: *gpu.CommandEncoder = undefined,
frame_render_pass: *gpu.RenderPassEncoder = undefined,
shapes_canvas: mach.EntityID = undefined,
triangle_canvas: mach.EntityID = undefined,
fps_timer: mach.Timer,
frame_count: usize,

polygon: Polygon,

pub const name = .app; // The main app has to be named .app
pub const Mod = mach.Mod(@This());

pub const systems = .{
    .init = .{ .handler = init },
    .deinit = .{ .handler = deinit },
    .after_init = .{ .handler = afterInit },
    .update = .{ .handler = update },
    .input = .{ .handler = tick_input },
    //.move = .{ .handler = tick_move },
    .render = .{ .handler = tick_render },
    .end_frame = .{ .handler = endFrame },
};

pub const components = .{
    .velocity = .{ .type = math.Vec2, .description = ""},
};

const Polygon = struct {
    vertices: std.ArrayList(Vec2),
    indices: std.ArrayList(u32),

    pub fn init(allocator: std.mem.Allocator) Polygon {
        return Polygon {
            .vertices = std.ArrayList(Vec2).init(allocator),
            .indices = std.ArrayList(u32).init(allocator),
        };
    }
    pub fn deinit(self: *Polygon) void {
        self.vertices.deinit();
        self.indices.deinit();
    } 

    pub fn add(self: *Polygon, p: Vec2) !void {
        std.debug.print("Add vertex: {} {}\n", .{p, self.vertices.items.len});
        try self.indices.append(@truncate(self.vertices.items.len));
        try self.vertices.append(p);
    }

    // transform
    // area
    // insert_polygon
    // rightmost_vertex
    // is_reflexive
    // merge_polygon
    // from_points

};

fn cross_2d(v1: Vec2, v2: Vec2) f32 {
    return v1.x() * v2.y() - v1.y() * v2.x();
}

fn hit_test_triangle(triangle: anytype, p: Vec2) bool {
    _ = triangle;
    _ = p;
    return false;   
}

// TOOD: return a pointer or index to the point?
fn hit_test_points(points: []Vec2, pos: Vec2, width: f32) ?Vec2 {
    for (points) |p| {
        if ((p.x()-width/2.0 <= pos.x() and pos.x() <= p.x()+width/2.0) and (p.y()-width/2.0 <= pos.y() and pos.y() <= p.y()+width/2.0)) {
            return p;
        }
    }
    return null;
}

fn window_to_canvas(core: *mach.Core.Mod, pos: mach.Core.Position) Vec2 {
    const window = core.state().main_window;
    const width:f32 = @floatFromInt(core.get(window, .width).?);
    const height:f32 = @floatFromInt(core.get(window, .height).?);
    var x: f32 = @floatCast(pos.x); x -= width / 2.0;
    var y: f32 = @floatCast(pos.y); y = -y + height / 2.0;
    return vec2(x, y);
}

fn init(
    self: *Mod,
    shapes: *ex_shapes.Mod,
) !void {
    shapes.schedule(.init);
    self.schedule(.after_init);    
}
fn deinit(
    shapes: *ex_shapes.Mod,
) !void {
    shapes.schedule(.deinit);
}

fn afterInit(
    self: *Mod,
    entities: *mach.Entities.Mod,
    shapes: *ex_shapes.Mod,
) !void {
    const allocator = gpa.allocator();

    const shapes_canvas = try entities.new();
    try  shapes.set(shapes_canvas, .shapes_pipeline, {});
    try  shapes.set(shapes_canvas, .pipeline, shapes_canvas);

    const triangle_canvas = try entities.new();
    try  shapes.set(triangle_canvas, .shapes_pipeline, {});
    try  shapes.set(triangle_canvas, .triangle_pipeline, triangle_canvas);

    shapes.schedule(.update);

    // TODO: need to change interface so there can be multiple pipelines per canvas

    self.init(.{
        .allocator = allocator,
        .shapes_canvas = shapes_canvas,
        .triangle_canvas = triangle_canvas,
        .fps_timer = try mach.Timer.start(),
        .frame_count = 0,
        .polygon = Polygon.init(allocator),
    });
}

fn update(
    self: *Mod,
    core: *mach.Core.Mod,
) !void {
    if (core.state().should_close) {
        return;
    }

    self.schedule(.input);
    //self.schedule(.move);
    self.schedule(.render);
}

fn tick_input(
    self: *Mod, 
    core: *mach.Core.Mod,
) !void {    
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
                const pos = window_to_canvas(core, ev.pos);
                try self.state().polygon.add(pos);
            },
            .mouse_release => |ev| {
                _ = ev;
            },
            .mouse_motion => |ev| {
                const pos = window_to_canvas(core, ev.pos);
                std.debug.print("Mouse move: {d:0.1} {d:0.1} \n", .{pos.x(), pos.y()});
            },
            .close => core.schedule(.exit),
            else => {},
        }
    }
}

fn tick_render(
    self: *Mod,
    entities: *mach.Entities.Mod,
    core: *mach.Core.Mod,
    shapes: *ex_shapes.Mod,
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
    const shapes_canvas = self.state().shapes_canvas;
    const triangle_canvas = self.state().triangle_canvas;

    // Clear all shapes
    // TODO: create a remove helper
    {
        var q = try entities.query(.{
            .ids = mach.Entities.Mod.read(.id),
            .pipelines = ex_shapes.Mod.read(.pipeline),
        });
        while (q.next()) |e| {
            for (e.ids, e.pipelines) |id, pipeline| {
                if (pipeline == shapes_canvas and id > 2) {
                    try entities.remove(id);
                }
            }
        }
    }

    {
        var q = try entities.query(.{
            .ids = mach.Entities.Mod.read(.id),
            .pipelines = ex_shapes.Mod.read(.triangle_pipeline),
        });
        while (q.next()) |e| {
            for (e.ids, e.pipelines) |id, pipeline| {
                if (pipeline == triangle_canvas and id > 2) {
                    try entities.remove(id);
                }
            }
        }
    }

    var canvas = Canvas{
        .entities = entities, 
        .shapes = shapes, 
        .canvas = shapes_canvas,
        .line_style = .{.color =  col(.MediumSlateBlue), .width = 2.0},
        .fill_style = .{.color =  col(.SkyBlue)},
    };

    const polygon = self.state().polygon;

    // Draw points for vertices
    // TODO: see if vertices could be stored as entities
    for (polygon.vertices.items) |pos| {
        const vertex = try drawCircle(&canvas, pos.x(), pos.y(), 20.0, 20.0);
        _ = vertex; // do anything to it?
    }

    // Draw lines
    if (polygon.indices.items.len > 1) 
    {
        canvas.line_style.width = 1.0;
        canvas.line_style.color = col(.White);    
        for (0..polygon.indices.items.len-1) |i| {
            const p0 = polygon.vertices.items[i];
            const p1 = polygon.vertices.items[i+1];
            const vertex = try drawLine(&canvas, p0.x(), p0.y(), p1.x(), p1.y());
            _ = vertex; // do anything to it?
        }
    }

    // Triangulate
    // Draw triangles
    {
        var tri_canvas = Canvas{
            .entities = entities, 
            .shapes = shapes, 
            .canvas = triangle_canvas,
            .line_style = .{.color =  col(.MediumSlateBlue), .width = 2.0},
            .fill_style = .{.color =  col(.CornFlowerBlue)},
        };

        _ = try drawTriangle(&tri_canvas, -100.0, -100.0, 0.0, 0.0, 100.0, -100.0);
        _ = try drawTriangle(&tri_canvas, -300.0, -100.0 + 100.0, -200.0, 0.0 + 100.0, -100.0, -100.0 + 100.0);
    }
    // Go through data and update
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
        "core-custom-entrypoint [ {d}fps ] [ Input {d}hz ]",
        .{
            // TODO(Core)
            core.state().frameRate(),
            core.state().inputRate(),
        },
    );

}
