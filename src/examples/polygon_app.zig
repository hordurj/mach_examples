const std = @import("std");
const assert = std.debug.assert;
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
const gm = @import("../geometry.zig");
const Polygon = gm.Polygon;
const Triangle = gm.Triangle;

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

polygon: Polygon,
polygon_list: std.ArrayList(Polygon),
polygon_changed: bool = false,
triangles: std.ArrayList(Triangle),

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

fn windowToCanvas(core: *mach.Core.Mod, pos: mach.Core.Position) Vec2 {
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
    self: *Mod,
    shapes: *ex_shapes.Mod,
) !void {
    shapes.schedule(.deinit);
    self.state().polygon.deinit();
    for (self.state().polygon_list.items) |*polygon| {
        polygon.deinit();
    }
    self.state().polygon_list.deinit();
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
        .polygon = Polygon.init(allocator),
        .polygon_list = std.ArrayList(Polygon).init(allocator),
        .triangles = std.ArrayList(Triangle).init(allocator),
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

fn clearPolygons(self: *Mod) void {
    self.state().polygon.clear();
    for (self.state().polygon_list.items) |*polygon| {
        polygon.deinit();
    }
    self.state().polygon_list.clearRetainingCapacity();
}

fn savePolygon(self: *Mod) !void {
    var string = std.ArrayList(u8).init(self.state().allocator);
    defer string.deinit();

    const file = try std.fs.cwd().createFile(
        "polygon.txt",
        .{ .truncate = true },
    );
    defer file.close();
    
    try string.writer().print("[",.{});
    for (self.state().polygon_list.items) |*polygon| {
        try std.json.stringify(polygon.vertices.items, .{}, string.writer());    
        try string.writer().print(",",.{});
    }
    try string.writer().print("[]]",.{});

    std.debug.print("Save: {s}\n", .{string.items});
    _ = try file.writer().write(string.items);
}

fn loadPolygon(self: *Mod) !void {
    const file = try std.fs.cwd().openFile("polygon.txt", .{.mode = .read_only});
    defer file.close();

    var buffered = std.io.bufferedReader(file.reader());
    var reader = buffered.reader();    
    const data = try reader.readAllAlloc(self.state().allocator, 4*1024*1024);
    defer self.state().allocator.free(data);

    std.debug.print("Load: {s}\n", .{data});

    const Polygons = [][]Vec2;
    const polygons = try std.json.parseFromSlice(Polygons, self.state().allocator, data, .{});
    defer polygons.deinit();

    clearPolygons(self);
    for (polygons.value) |polygon| {    
        if (polygon.len > 0) {
            var new_polygon = Polygon.init(self.state().allocator);
            for (polygon) |v| {
                try new_polygon.add(v);
            }
            try self.state().polygon_list.append(new_polygon);
        }    
    }
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
                    .c => {
                        // Clear
                        clearPolygons(self);
                        self.state().polygon_changed = true;
                    },
                    .s => {
                        // Save polygon
                        try savePolygon(self);
                    },
                    .l => {
                        // Load polygon
                        try loadPolygon(self);
                        self.state().polygon_changed = true;
                    },
                    else => {},
                }
            },
            .mouse_press => |ev| {
                switch (ev.button) {
                    .left => {
                        // TODO: need a screen to world transformation
                        const pos = windowToCanvas(core, ev.pos);
                        if (self.state().polygon_list.items.len == 0) {
                            const new_polygon = Polygon.init(self.state().allocator);
                            try self.state().polygon_list.append(new_polygon);
                        }
                        try self.state().polygon_list.items[self.state().polygon_list.items.len-1].add(pos);
                        self.state().polygon_changed = true;
                    },
                    .right => {
                        if (self.state().polygon_list.items.len > 0) {                        
                            if (self.state().polygon_list.getLast().indices.items.len > 2) {
                                // start a new path                        
                                const new_polygon = Polygon.init(self.state().allocator);
                                try self.state().polygon_list.append(new_polygon);
                            } else {
                                self.state().polygon_list.items[self.state().polygon_list.items.len-1].clear();
                            }
                        }
                    },
                    else => {}
                }
            },
            .mouse_release => |_| {
            },
            .mouse_motion => |_| {
                //const pos = window_to_canvas(core, ev.pos);
                //std.debug.print("Mouse move: {d:0.1} {d:0.1} \n ", .{pos.x(), pos.y()});
            },
            .close => core.schedule(.exit),
            else => {},
        }
    }
}

fn polygonFurtherRight(context: void, lhs: *Polygon, rhs: *Polygon) bool {
    _ = context;
    return lhs.rightmostVertex().vertex.x() > rhs.rightmostVertex().vertex.x();
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

    if (self.state().polygon_changed)
    {
        const polygon = &self.state().polygon;
        polygon.clear();

        if (self.state().polygon_list.items.len > 0) {
            try polygon.indices.appendSlice(self.state().polygon_list.items[0].indices.items);
            try polygon.vertices.appendSlice(self.state().polygon_list.items[0].vertices.items);

            var polygons = std.ArrayList(*Polygon).init(self.state().allocator);
            defer polygons.deinit();
            _ = try polygons.addManyAsSlice(self.state().polygon_list.items.len-1);
            for (1..self.state().polygon_list.items.len) |i| {
                polygons.items[i-1] = &self.state().polygon_list.items[i];    
            }
            std.sort.pdq(*Polygon, polygons.items, {}, polygonFurtherRight);
            for (polygons.items) |next_polygon| {
                if (next_polygon.vertices.items.len > 2) {
                    try polygon.merge(next_polygon);
                }
            }
        }

        // Clear all shapes
        // TODO: create a remove helper
        const t_start_delete: i64 = std.time.microTimestamp();
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
        const t_delete_time: f32 = @floatFromInt(std.time.microTimestamp() - t_start_delete);
        std.debug.print("Deleting shapes took {d:.1} ms\n", .{t_delete_time/1000.0});

        var canvas = Canvas{
            .entities = entities, 
            .shapes = shapes, 
            .canvas = shapes_canvas,
            .line_style = .{.color =  col(.MediumSlateBlue), .width = 2.0},
            .fill_style = .{.color =  col(.SkyBlue)},
        };

        var triangles = &self.state().triangles; 

        // Triangulate
        // Draw triangles
        {
            const t_start_draw: i64 = std.time.microTimestamp();

            var tri_canvas = Canvas{
                .entities = entities, 
                .shapes = shapes, 
                .canvas = triangle_canvas,
                .line_style = .{.color =  col(.MediumSlateBlue), .width = 2.0},
                .fill_style = .{.color =  col(.CornFlowerBlue)},
            };

            if (polygon.indices.items.len > 2) {
                if (self.state().polygon_changed) {
                    triangles.clearRetainingCapacity();
                    const t_start: i64 = std.time.microTimestamp();
                    _ = try gm.triangulate(polygon, triangles);
                    const t: f32 = @floatFromInt(std.time.microTimestamp() - t_start);
                    std.debug.print("Triangulating {} vertices took {} ms\n", .{polygon.indices.items.len, t/1000.0});
                    self.state().polygon_changed = false;                
                }

                // Draw triangles
                for (triangles.items) |t| {
                    const v0 = polygon.vertices.items[t[0]];
                    const v1 = polygon.vertices.items[t[1]];
                    const v2 = polygon.vertices.items[t[2]];
                    _ = try drawTriangle(&tri_canvas, 
                        v0.x(), v0.y(),
                        v1.x(), v1.y(),
                        v2.x(), v2.y(),
                    );
                }

                if (false) {
                    canvas.line_style = .{.color =  col(.Yellow), .width = 2.0};
                    for (triangles.items) |t| {
                        const v0 = polygon.vertices.items[t[0]];
                        const v1 = polygon.vertices.items[t[1]];
                        const v2 = polygon.vertices.items[t[2]];

                        _ = try drawLine(&canvas, v0.x(), v0.y(), v1.x(), v1.y());
                        _ = try drawLine(&canvas, v1.x(), v1.y(), v2.x(), v2.y());
                        _ = try drawLine(&canvas, v2.x(), v2.y(), v0.x(), v0.y());
                    }
                }
            } 

            const t_draw_time: f32 = @floatFromInt(std.time.microTimestamp() - t_start_draw);
            std.debug.print("Drawing triangles took {d:.1} ms\n", .{t_draw_time/1000.0});

            // Draw lines
            if (true)
            {
                canvas.line_style = .{.color =  col(.White), .width = 2.0};
                if (polygon.indices.items.len > 1) 
                {
                    canvas.line_style.width = 2.0;
                    canvas.line_style.color = col(.Red);    
                    const N = polygon.indices.items.len;
                    for (0..N) |i| {
                        const p0 = polygon.vertices.items[polygon.indices.items[i % N]];
                        const p1 = polygon.vertices.items[polygon.indices.items[(i+1) % N]];
                        const vertex = try drawLine(&canvas, p0.x(), p0.y(), p1.x(), p1.y());
                        _ = vertex; // do anything to it?
                    }
                }
            }
            self.state().polygon_changed = false;
        }

        // Draw points for vertices
        // TODO: see if vertices could be stored as entities
        canvas.fill_style.color = col(.Orange);
        canvas.line_style.color = col(.DarkGrey);
        if (false) {
            for (polygon.vertices.items) |pos| {
                const vertex = try drawCircle(&canvas, pos.x(), pos.y(), 15.0, 15.0);
                _ = vertex; // do anything to it?
            }
        }

    }
    // Go through data and update
    shapes.state().render_pass = self.state().frame_render_pass;
    shapes.schedule(.update_shapes);        // Only happens if shapes have changed
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
        "Polygon example [ {d}fps ] ", //[ Input {d}hz ]
        .{
            core.state().frameRate(),
//            core.state().inputRate(),
        },
    );

}
