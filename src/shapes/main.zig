//! Shapes module
//!
//! Can draw various shapes, including: rectangles, lines, and circles.
//!
//! Handles multiple pipelines.
//!
const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;
const gfx = mach.gfx;
const math = mach.math;
const Mat4x4 = math.Mat4x4;
const Vec2 = math.Vec2;
const vec2 = math.vec2;
const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Vec4 = math.Vec4;
const vec4 = math.vec4;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// Resources
allocator: std.mem.Allocator,
/// Which render pass should be used during .render
render_pass: ?*gpu.RenderPassEncoder = null,

pub const components = .{
    .view_projection = .{ .type = math.Mat4x4, .description = "" },
    .transform = .{ .type = Mat4x4, .description = "Shape transformation" },
    .shader = .{ .type = *gpu.ShaderModule, .description = "" },
    .blend_state = .{ .type = gpu.BlendState, .description = "" },
    .bind_group_layout = .{ .type = *gpu.BindGroupLayout, .description = "" },
    .bind_group = .{ .type = *gpu.BindGroup, .description = "" },
    .color_target_state = .{ .type = gpu.ColorTargetState, .description = "" },
    .fragment_state = .{ .type = gpu.FragmentState, .description = "" },
    .layout = .{ .type = *gpu.PipelineLayout, .description = "" },
    .num_shapes = .{ .type = u32, .description = "" },

    .shapes_pipeline = .{ .type = void },
    .rectangle = .{ .type = Rectangle },
    .color = .{ .type = Vec4 },
    .line = .{ .type = Line },
    .triangle = .{ .type = Triangle },
    .path = .{ .type = Path },         // .polygon
    //    .quadratic   .cubic
    .circle = .{ .type = Circle },
    .line_style = .{ .type = LineStyle },
    .fill_style = .{ .type = FillStyle },

    .triangle_pipeline = .{ .type = mach.EntityID },
    .pipeline = .{ .type = mach.EntityID },
    .built = .{ .type = BuiltPipeline, .description = "internal" },
    .built_triangle = .{ .type = BuiltTrianglePipeline, .description = "internal" },
};

pub const ShapeType = enum(u32) {
    rect = 1,
    circle = 2,
    line = 3,
    quad = 4,
    cubic = 5,
};

// TODO: Create a canvas/context for draw calls
// TODO: Document available params
//          e.g. fill color, stroke, fill, line ends, ....
//
// TODO: Shapes
//          triangles
//          polygons
//          arc
//          bezier curves
// TODO: Features
//          gradients
//          join styles
//          endcaps
//          ...

pub fn col(c: NamedColor) Vec4 {
    const v: u32 = @intFromEnum(c);
    const r = (v >> 16) & 0xFF;
    const g = (v >> 8) & 0xFF;
    const b = v & 0xFF;
    return rgb(r, g, b);
}

/// Converts rgb to Vec4 in range 0..1 per component.
/// Alpha is set to one
/// If r,g,b are integer it is assumed they are in the range
/// 0..255
pub fn rgb(r: anytype, g: anytype, b: anytype) Vec4 {
    if (@TypeOf(r) == @TypeOf(g) and @TypeOf(g) == @TypeOf(b)) {
        switch (@typeInfo(@TypeOf(r))) {
            .ComptimeInt, .Int => {
                return vec4(@as(f32, @floatFromInt(r)) / 255.0, @as(f32, @floatFromInt(g)) / 255.0, @as(f32, @floatFromInt(b)) / 255.0, 1.0);
            },
            .ComptimeFloat, .Float => {
                return vec4(r, g, b, 1.0);
            },
            else => {
                @compileError("r,g,b need to be Int or Float");
            },
        }
    } else {
        @compileError("r,g,b need to be of same type.");
    }
}

// hsv
// hsl
// cmyk
// palettes
// ...

pub const FillStyle = struct {
    color: Vec4 = col(.White),
};

pub const LineStyle = struct {
    color: Vec4 = vec4(1.0, 1.0, 1.0, 1.0),
    width: f32 = 1.0,
};

pub const Canvas = struct {
    entities: *mach.Entities.Mod,
    shapes: *Mod,
    canvas: mach.EntityID,
    line_style: LineStyle,
    fill_style: FillStyle,
};

// Naming: rect, drawRect, strokeRect, fillRect ???

// Function interface
pub fn drawRect(
    canvas: *const Canvas,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    // color: Vec4    Optionally override canvas state?
) !mach.EntityID {
    const rect = try canvas.entities.new();
    try canvas.shapes.set(rect, .pipeline, canvas.canvas);
    try canvas.shapes.set(rect, .transform, Mat4x4.translate(vec3(0.0, 0.0, 0.0)));
    try canvas.shapes.set(rect, .rectangle, .{
        .center = vec2(x, y),
        .size = vec2(width, height),
    });
    try canvas.shapes.set(rect, .line_style, canvas.line_style);
    try canvas.shapes.set(rect, .fill_style, canvas.fill_style);
    return rect;
}

pub fn drawCircle(
    canvas: *Canvas,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    //color: Vec4
) !mach.EntityID {
    const circle = try canvas.entities.new();
    try canvas.shapes.set(circle, .pipeline, canvas.canvas);
    try canvas.shapes.set(circle, .transform, Mat4x4.translate(vec3(0.0, 0.0, 0.0)));
    try canvas.shapes.set(circle, .circle, .{ .center = vec2(x, y), .size = vec2(width, height) });
    try canvas.shapes.set(circle, .line_style, canvas.line_style);
    try canvas.shapes.set(circle, .fill_style, canvas.fill_style);
    return circle;
}

pub fn drawLine(
    canvas: *Canvas,
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
) !mach.EntityID {
    const line = try canvas.entities.new();
    try canvas.shapes.set(line, .pipeline, canvas.canvas);
    try canvas.shapes.set(line, .transform, Mat4x4.translate(vec3(0.0, 0.0, 0.0)));
    try canvas.shapes.set(line, .line, .{
        .start = vec2(x0, y0),
        .finish = vec2(x1, y1),
    });
    try canvas.shapes.set(line, .line_style, canvas.line_style);
    try canvas.shapes.set(line, .fill_style, canvas.fill_style); // Included for consistency for other shapes.

    return line;
}

pub fn drawTriangle(
    canvas: *const Canvas,
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
) !mach.EntityID {
    const triangle = try canvas.entities.new();
    try canvas.shapes.set(triangle, .triangle_pipeline, canvas.canvas);
    try canvas.shapes.set(triangle, .transform, Mat4x4.translate(vec3(0.0, 0.0, 0.0)));
    try canvas.shapes.set(triangle, .triangle, .{
        .p0 = vec4(x0, y0, 0.0, 1.0),
        .p1 = vec4(x1, y1, 0.0, 1.0),
        .p2 = vec4(x2, y2, 0.0, 1.0),
    });
    try canvas.shapes.set(triangle, .line_style, canvas.line_style);
    try canvas.shapes.set(triangle, .fill_style, canvas.fill_style);

    return triangle;
}

pub fn drawPolygon(
    canvas: *const Canvas,
    vertices: []Vec2,
) !mach.EntityID {
    // TODO : add support for polygon fill
    const polygon = try canvas.entities.new();
    try canvas.shapes.set(polygon, .pipeline, canvas.canvas);
    try canvas.shapes.set(polygon, .transform, Mat4x4.translate(vec3(0.0, 0.0, 0.0)));
    try canvas.shapes.set(polygon, .path, .{.vertices = vertices, .close = true});
    try canvas.shapes.set(polygon, .line_style, canvas.line_style);
    try canvas.shapes.set(polygon, .fill_style, canvas.fill_style);

    return polygon;
}

// drawPath, quadratic, cubic, ...
// groups

pub const name = .shapes; // The main app has to be named .app
pub const Mod = mach.Mod(@This());

pub const systems = .{
    .init = .{ .handler = init },
    .deinit = .{ .handler = deinit },
    .update = .{ .handler = update },
    .update_shapes = .{ .handler = updateShapes },
    .pre_render = .{ .handler = preRender },
    .render = .{ .handler = render },
};

pub const Rectangle = struct {
    center: Vec2,
    size: Vec2,
};

pub const Circle = struct {
    center: Vec2,
    size: Vec2,
};

pub const Line = struct {
    start: Vec2,
    finish: Vec2,
};

pub const Triangle = struct {
    p0: Vec4,
    p1: Vec4,
    p2: Vec4,
};

pub const Path = struct {
    vertices: []Vec2,
    close: bool = true,
};

pub const Color = struct {
    color: Vec4,
};

const Uniforms = extern struct {
    // WebGPU requires that the size of struct fields are multiples of 16
    // So we use align(16) and 'extern' to maintain field order

    /// The view * orthographic projection matrix
    view_projection: math.Mat4x4 align(16),
};

const UintParams = extern struct {
    param1: [4]u32,
};

const FloatParams = extern struct {
    line_color: math.Vec4,
    fill_color: math.Vec4,
    param3: math.Vec4,
    gradient_end_color: math.Vec4,
};
const shape_buffer_cap = 10000;
// Shape buffers
pub var cp_transforms: [shape_buffer_cap]math.Mat4x4 = undefined;
pub var cp_center: [shape_buffer_cap]math.Vec2 = undefined;
pub var cp_size: [shape_buffer_cap]math.Vec2 = undefined;
pub var cp_float_params: [shape_buffer_cap]FloatParams = undefined;
pub var cp_uint_params: [shape_buffer_cap]UintParams = undefined;

// Triangle buffers
pub var cp_vertices: [shape_buffer_cap * 2]math.Vec4 = undefined;
pub var cp_colors: [shape_buffer_cap]math.Vec4 = undefined;

pub const BuiltTrianglePipeline = struct {
    render: *gpu.RenderPipeline,
    bind_group: *gpu.BindGroup,
    uniforms: *gpu.Buffer,
    vertices: *gpu.Buffer,

    pub fn deinit(p: *const BuiltTrianglePipeline) void {
        p.render.release();
        p.bind_group.release();
        p.uniforms.release();
        p.vertices.release();
    }
};

pub const BuiltPipeline = struct {
    render: *gpu.RenderPipeline,
    bind_group: *gpu.BindGroup,
    uniforms: *gpu.Buffer,
    transforms: *gpu.Buffer,
    positions: *gpu.Buffer,
    sizes: *gpu.Buffer,
    uint_params: *gpu.Buffer,
    float_params: *gpu.Buffer,

    pub fn deinit(p: *const BuiltPipeline) void {
        p.render.release();
        p.bind_group.release();
        p.uniforms.release();
        p.transforms.release();
        p.positions.release();
        p.sizes.release();
        p.uint_params.release();
        p.float_params.release();
    }
};

fn init(self: *Mod) void {
    const allocator = gpa.allocator();

    self.init(.{
        .allocator = allocator,
    });
}

fn deinit(self: *Mod, entities: *mach.Entities.Mod) !void {
    _ = self;

    {
        var q = try entities.query(.{
            .built_pipelines = Mod.read(.built_triangle),
        });
        while (q.next()) |v| {
            for (v.built_pipelines) |built| {
                built.deinit();
            }
        }
    }

    {
        var q = try entities.query(.{
            .built_pipelines = Mod.read(.built),
        });
        while (q.next()) |v| {
            for (v.built_pipelines) |built| {
                built.deinit();
            }
        }
    }
}

fn updateTriangles(
    entities: *mach.Entities.Mod,
    core: *mach.Core.Mod,
) !void {
    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .shape_pipelines = Mod.read(.shapes_pipeline),
        .built_pipelines = Mod.read(.built_triangle),
        .num_shapes = Mod.write(.num_shapes),
    });
    while (q.next()) |v| {
        for (v.ids, v.built_pipelines, v.num_shapes) |pipeline_id, built, *num_shapes| {
            num_shapes.* = 0;

            var sq = try entities.query(.{
                .ids = mach.Entities.Mod.read(.id),
                .triangle_pipelines = Mod.read(.triangle_pipeline),
                .transforms = Mod.read(.transform),
                .triangles = Mod.read(.triangle),
                .line_style = Mod.read(.line_style),
                .fill_style = Mod.read(.fill_style),
            });
            while (sq.next()) |w| {
                for (w.ids, w.triangle_pipelines, w.transforms, w.triangles, w.line_style, w.fill_style) |shape_id, triangle_pipeline_id, transform, triangle, line_style, fill_style| {
                    _ = shape_id;
                    _ = line_style;
                    if (pipeline_id == triangle_pipeline_id) {
                        //std.debug.print("Update triangles {} {}\n", .{num_shapes.*, fill_style.color});
                        // TODO apply transform
                        _ = transform;
                        //_ = triangle;
                        //cp_transforms[num_shapes.*] = transform; // Apply transform?
                        cp_vertices[6 * num_shapes.* + 0] = triangle.p0;
                        cp_vertices[6 * num_shapes.* + 1] = fill_style.color;

                        cp_vertices[6 * num_shapes.* + 2] = triangle.p1;
                        cp_vertices[6 * num_shapes.* + 3] = fill_style.color;

                        cp_vertices[6 * num_shapes.* + 4] = triangle.p2;
                        cp_vertices[6 * num_shapes.* + 5] = fill_style.color;

                        num_shapes.* += 1;
                    }
                }
            }

            if (num_shapes.* > 0) {
                const device = core.state().device;
                const label = @tagName(name) ++ ".updateTriangles";
                const encoder = device.createCommandEncoder(&.{ .label = label });
                defer encoder.release();
                encoder.writeBuffer(built.vertices, 0, cp_vertices[0 .. num_shapes.* * 3 * 2]);

                var command = encoder.finish(&.{ .label = label }); // Encoder leaks if finish not called
                defer command.release();
                core.state().queue.submit(&[_]*gpu.CommandBuffer{command});
            }
        }
    }
}

fn updateShapes(
    self: *Mod,
    entities: *mach.Entities.Mod,
    core: *mach.Core.Mod,
) !void {
    _ = self;

    try updateTriangles(entities, core);

    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .shape_pipelines = Mod.read(.shapes_pipeline),
        .built_pipelines = Mod.read(.built),
        .num_shapes = Mod.write(.num_shapes),
    });
    while (q.next()) |v| {
        for (v.ids, v.built_pipelines, v.num_shapes) |pipeline_id, built, *num_shapes| {
            num_shapes.* = 0;
            {
                var sq = try entities.query(.{
                    .ids = mach.Entities.Mod.read(.id),
                    .shape_pipelines = Mod.read(.pipeline),
                    .transforms = Mod.read(.transform),
                    .rectangles = Mod.read(.rectangle),
                    .line_style = Mod.read(.line_style),
                    .fill_style = Mod.read(.fill_style),
                });
                while (sq.next()) |w| {
                    for (w.ids, w.shape_pipelines, w.transforms, w.rectangles, w.line_style, w.fill_style) |shape_id, shape_pipeline_id, transform, rectangle, line_style, fill_style| {
                        _ = shape_id;
                        if (pipeline_id == shape_pipeline_id) {
                            cp_transforms[num_shapes.*] = transform;
                            cp_center[num_shapes.*] = rectangle.center;
                            cp_size[num_shapes.*] = rectangle.size;
                            cp_uint_params[num_shapes.*] =
                                .{
                                .param1 = [4]u32{ @intFromEnum(ShapeType.rect), 0, 0, 0 },
                            };
                            cp_float_params[num_shapes.*] =
                                .{
                                .line_color = line_style.color,
                                .fill_color = fill_style.color,
                                .param3 = vec4(line_style.width, 0.0, 0.0, 0.0),
                                .gradient_end_color = vec4(0.0, 0.0, 0.0, 0.0),
                            };
                            num_shapes.* += 1;
                        }
                    }
                }
            }
            {
                var sq = try entities.query(.{
                    .ids = mach.Entities.Mod.read(.id),
                    .shape_pipelines = Mod.read(.pipeline),
                    .transforms = Mod.read(.transform),
                    .circles = Mod.read(.circle),
                    .line_style = Mod.read(.line_style),
                    .fill_style = Mod.read(.fill_style),
                });
                while (sq.next()) |w| {
                    for (w.ids, w.shape_pipelines, w.transforms, w.circles, w.line_style, w.fill_style) |shape_id, shape_pipeline_id, transform, circle, line_style, fill_style| {
                        _ = shape_id;
                        if (pipeline_id == shape_pipeline_id) {
                            cp_transforms[num_shapes.*] = transform;
                            cp_center[num_shapes.*] = circle.center;
                            cp_size[num_shapes.*] = circle.size;
                            cp_uint_params[num_shapes.*] = .{
                                .param1 = [4]u32{ @intFromEnum(ShapeType.circle), 0, 0, 0 },
                            };
                            cp_float_params[num_shapes.*] =
                                .{
                                .line_color = line_style.color,
                                .fill_color = fill_style.color,
                                .param3 = vec4(line_style.width, 0.0, 0.0, 0.0),
                                .gradient_end_color = vec4(0.0, 0.0, 0.0, 0.0),
                            };
                            num_shapes.* += 1;
                        }
                    }
                }
            }
            {
                var sq = try entities.query(.{
                    .ids = mach.Entities.Mod.read(.id),
                    .shape_pipelines = Mod.read(.pipeline),
                    .transforms = Mod.read(.transform),
                    .lines = Mod.read(.line),
                    .line_style = Mod.read(.line_style),
                });
                while (sq.next()) |w| {
                    for (w.ids, w.shape_pipelines, w.transforms, w.lines, w.line_style) |shape_id, shape_pipeline_id, transform, line, line_style| {
                        _ = shape_id;
                        if (pipeline_id == shape_pipeline_id) {
                            cp_transforms[num_shapes.*] = transform;
                            cp_center[num_shapes.*] = line.start;
                            cp_size[num_shapes.*] = line.finish;
                            cp_uint_params[num_shapes.*] =
                                .{
                                .param1 = [4]u32{ @intFromEnum(ShapeType.line), 0, 0, 0 },
                            };
                            cp_float_params[num_shapes.*] =
                                .{
                                .line_color = line_style.color,
                                .fill_color = col(.Black),
                                .param3 = vec4(line_style.width, 0.0, 0.0, 0.0),
                                .gradient_end_color = vec4(0.0, 0.0, 0.0, 0.0),
                            };
                            num_shapes.* += 1;
                        }
                    }
                }
            }

            {
                var sq = try entities.query(.{
                    .ids = mach.Entities.Mod.read(.id),
                    .shape_pipelines = Mod.read(.pipeline),
                    .transforms = Mod.read(.transform),
                    .paths = Mod.read(.path),
                    .line_style = Mod.read(.line_style),
                });
                while (sq.next()) |w| {
                    for (w.ids, w.shape_pipelines, w.transforms, w.paths, w.line_style) |shape_id, shape_pipeline_id, transform, path, line_style| {
                        _ = shape_id;
                        if (pipeline_id == shape_pipeline_id) {
                            if (path.vertices.len == 0) { continue; }

                            const first_p = path.vertices[0];
                            var prev_p = first_p;
                            for (path.vertices[1..]) |p| {
                                // TODO : refactor into an add line function
                                cp_transforms[num_shapes.*] = transform;
                                cp_center[num_shapes.*] = prev_p;
                                cp_size[num_shapes.*] = p;
                                cp_uint_params[num_shapes.*] = .{
                                    .param1 = [4]u32{ @intFromEnum(ShapeType.line), 0, 0, 0 },
                                };
                                cp_float_params[num_shapes.*] = .{
                                    .line_color = line_style.color,
                                    .fill_color = col(.Black),
                                    .param3 = vec4(line_style.width, 0.0, 0.0, 0.0),
                                    .gradient_end_color = vec4(0.0, 0.0, 0.0, 0.0),
                                };
                                num_shapes.* += 1;
                                prev_p = p;
                            }
                            if (path.close) {
                                cp_transforms[num_shapes.*] = transform;
                                cp_center[num_shapes.*] = prev_p;
                                cp_size[num_shapes.*] = first_p;
                                cp_uint_params[num_shapes.*] = .{
                                    .param1 = [4]u32{ @intFromEnum(ShapeType.line), 0, 0, 0 },
                                };
                                cp_float_params[num_shapes.*] = .{
                                    .line_color = line_style.color,
                                    .fill_color = col(.Black),
                                    .param3 = vec4(line_style.width, 0.0, 0.0, 0.0),
                                    .gradient_end_color = vec4(0.0, 0.0, 0.0, 0.0),
                                };
                                num_shapes.* += 1;                                
                            }
                        }
                    }
                }
            }

            if (num_shapes.* > 0) {
                const device = core.state().device;
                const label = @tagName(name) ++ ".updateShapes";
                const encoder = device.createCommandEncoder(&.{ .label = label });
                defer encoder.release();

                encoder.writeBuffer(built.transforms, 0, cp_transforms[0..num_shapes.*]);
                encoder.writeBuffer(built.positions, 0, cp_center[0..num_shapes.*]);
                encoder.writeBuffer(built.sizes, 0, cp_size[0..num_shapes.*]);
                encoder.writeBuffer(built.uint_params, 0, cp_uint_params[0..num_shapes.*]);
                encoder.writeBuffer(built.float_params, 0, cp_float_params[0..num_shapes.*]);

                var command = encoder.finish(&.{ .label = label }); // Encoder leaks if finish not called
                defer command.release();
                core.state().queue.submit(&[_]*gpu.CommandBuffer{command});
            }
        }
    }
}

/// Update the pipeline buffers with the shape data.
fn update(
    self: *Mod,
    entities: *mach.Entities.Mod,
    core: *mach.Core.Mod,
) !void {
    try deinit(self, entities);

    {
        var q = try entities.query(.{
            .ids = mach.Entities.Mod.read(.id),
            .shape_pipelines = Mod.read(.shapes_pipeline),
            .pipelines = Mod.read(.triangle_pipeline),
        });
        while (q.next()) |v| {
            for (v.ids) |pipeline_id| {
                try buildTrianglePipeline(self, core, pipeline_id);
            }
        }
    }

    {
        var q = try entities.query(.{
            .ids = mach.Entities.Mod.read(.id),
            .shape_pipelines = Mod.read(.shapes_pipeline),
            .pipelines = Mod.read(.pipeline),
        });
        while (q.next()) |v| {
            for (v.ids) |pipeline_id| {
                try buildPipeline(self, core, pipeline_id);
            }
        }
    }
}

fn buildTrianglePipeline(
    self: *Mod,
    core: *mach.Core.Mod,
    pipeline_id: mach.EntityID,
) !void {
    const opt_shader = self.get(pipeline_id, .shader);
    const opt_blend_state = self.get(pipeline_id, .blend_state);
    const opt_bind_group_layout = self.get(pipeline_id, .bind_group_layout);
    const opt_bind_group = self.get(pipeline_id, .bind_group);
    const opt_color_target_state = self.get(pipeline_id, .color_target_state);
    const opt_fragment_state = self.get(pipeline_id, .fragment_state);
    const opt_layout = self.get(pipeline_id, .layout);

    const device = core.state().device;
    const label = @tagName(name) ++ ".buildTrianglePipeline";

    const vertex_attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x4, .offset = 0, .shader_location = 0 },
        .{ .format = .float32x4, .offset = 16, .shader_location = 1 },
    };

    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = 32, // pos, col
        .step_mode = .vertex,
        .attributes = &vertex_attributes,
    });

    const vertices = device.createBuffer(&.{
        .label = label ++ " vertices",
        .usage = .{ .vertex = true, .copy_dst = true },
        .size = @sizeOf(math.Vec4) * shape_buffer_cap * 2,
        .mapped_at_creation = .false,
    });

    const uniforms = device.createBuffer(&.{
        .label = label ++ " uniforms",
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(Uniforms),
        .mapped_at_creation = .false,
    });
    const bind_group_layout = opt_bind_group_layout orelse device.createBindGroupLayout(
        &gpu.BindGroupLayout.Descriptor.init(.{
            .label = label,
            .entries = &.{
                gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true }, .uniform, false, 0),
            },
        }),
    );
    defer bind_group_layout.release();

    const bind_group = opt_bind_group orelse device.createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .label = label,
            .layout = bind_group_layout,
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, uniforms, 0, @sizeOf(Uniforms), @sizeOf(Uniforms)),
            },
        }),
    );

    const blend_state = opt_blend_state orelse gpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .zero,
        },
    };

    const shader_module = opt_shader orelse device.createShaderModuleWGSL("triangle.wgsl", @embedFile("triangle.wgsl"));
    defer shader_module.release();

    const color_target = opt_color_target_state orelse gpu.ColorTargetState{
        .format = core.get(core.state().main_window, .framebuffer_format).?,
        .blend = &blend_state,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = opt_fragment_state orelse gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "fragMain",
        .targets = &.{color_target},
    });

    const bind_group_layouts = [_]*gpu.BindGroupLayout{bind_group_layout};
    const pipeline_layout = opt_layout orelse device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .label = label,
        .bind_group_layouts = &bind_group_layouts,
    }));
    defer pipeline_layout.release();

    const primitive_pipeline_state = gpu.PrimitiveState{
        .topology = .triangle_list,
        //.front_face = .ccw,
        //.cull_mode = .back,
    };

    const render_pipeline = device.createRenderPipeline(&gpu.RenderPipeline.Descriptor{
        .label = label,
        .fragment = &fragment,
        .layout = pipeline_layout,
        .primitive = primitive_pipeline_state,
        .vertex = gpu.VertexState.init(.{
            .module = shader_module,
            .entry_point = "vertMain",
            .buffers = &.{vertex_buffer_layout},
        }),
    });

    const built = BuiltTrianglePipeline{
        .render = render_pipeline,
        .bind_group = bind_group,
        .uniforms = uniforms,
        .vertices = vertices,
    };
    try self.set(pipeline_id, .built_triangle, built);
    try self.set(pipeline_id, .num_shapes, 0);
}

fn buildPipeline(
    self: *Mod,
    core: *mach.Core.Mod,
    pipeline_id: mach.EntityID,
) !void {
    const opt_shader = self.get(pipeline_id, .shader);
    const opt_blend_state = self.get(pipeline_id, .blend_state);
    const opt_bind_group_layout = self.get(pipeline_id, .bind_group_layout);
    const opt_bind_group = self.get(pipeline_id, .bind_group);
    const opt_color_target_state = self.get(pipeline_id, .color_target_state);
    const opt_fragment_state = self.get(pipeline_id, .fragment_state);
    const opt_layout = self.get(pipeline_id, .layout);

    const device = core.state().device;
    const label = @tagName(name) ++ ".buildPipeline";

    // Storage buffers
    const transforms = device.createBuffer(&.{
        .label = label ++ " transforms",
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf(math.Mat4x4) * shape_buffer_cap,
        .mapped_at_creation = .false,
    });

    const positions = device.createBuffer(&.{
        .label = label ++ " positions",
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf(math.Vec2) * shape_buffer_cap,
        .mapped_at_creation = .false,
    });

    const sizes = device.createBuffer(&.{
        .label = label ++ " sizes",
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf(math.Vec2) * shape_buffer_cap,
        .mapped_at_creation = .false,
    });

    const uint_params = device.createBuffer(&.{
        .label = label ++ " uint params",
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf(UintParams) * shape_buffer_cap,
        .mapped_at_creation = .false,
    });

    const float_params = device.createBuffer(&.{
        .label = label ++ " float params",
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf(FloatParams) * shape_buffer_cap,
        .mapped_at_creation = .false,
    });

    const uniforms = device.createBuffer(&.{
        .label = label ++ " uniforms",
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(Uniforms),
        .mapped_at_creation = .false,
    });
    const bind_group_layout = opt_bind_group_layout orelse device.createBindGroupLayout(
        &gpu.BindGroupLayout.Descriptor.init(.{
            .label = label,
            .entries = &.{
                gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true }, .uniform, false, 0),
                gpu.BindGroupLayout.Entry.buffer(1, .{ .vertex = true }, .read_only_storage, false, 0),
                gpu.BindGroupLayout.Entry.buffer(2, .{ .vertex = true, .fragment = true }, .read_only_storage, false, 0),
                gpu.BindGroupLayout.Entry.buffer(3, .{ .vertex = true, .fragment = true }, .read_only_storage, false, 0),
                gpu.BindGroupLayout.Entry.buffer(4, .{ .vertex = true, .fragment = true }, .read_only_storage, false, 0),
                gpu.BindGroupLayout.Entry.buffer(5, .{ .vertex = true, .fragment = true }, .read_only_storage, false, 0),
            },
        }),
    );
    defer bind_group_layout.release();

    const bind_group = opt_bind_group orelse device.createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .label = label,
            .layout = bind_group_layout,
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, uniforms, 0, @sizeOf(Uniforms), @sizeOf(Uniforms)),
                gpu.BindGroup.Entry.buffer(1, transforms, 0, @sizeOf(math.Mat4x4) * shape_buffer_cap, @sizeOf(math.Mat4x4)),
                gpu.BindGroup.Entry.buffer(2, positions, 0, @sizeOf(math.Vec2) * shape_buffer_cap, @sizeOf(math.Vec2)),
                gpu.BindGroup.Entry.buffer(3, sizes, 0, @sizeOf(math.Vec2) * shape_buffer_cap, @sizeOf(math.Vec2)),
                gpu.BindGroup.Entry.buffer(4, uint_params, 0, @sizeOf(UintParams) * shape_buffer_cap, @sizeOf(UintParams)),
                gpu.BindGroup.Entry.buffer(5, float_params, 0, @sizeOf(FloatParams) * shape_buffer_cap, @sizeOf(FloatParams)),
            },
        }),
    );

    const blend_state = opt_blend_state orelse gpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .zero,
        },
    };

    const shader_module = opt_shader orelse device.createShaderModuleWGSL("shapes.wgsl", @embedFile("shapes.wgsl"));
    defer shader_module.release();

    const color_target = opt_color_target_state orelse gpu.ColorTargetState{
        .format = core.get(core.state().main_window, .framebuffer_format).?,
        .blend = &blend_state,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = opt_fragment_state orelse gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "fragMain",
        .targets = &.{color_target},
    });

    const bind_group_layouts = [_]*gpu.BindGroupLayout{bind_group_layout};
    const pipeline_layout = opt_layout orelse device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .label = label,
        .bind_group_layouts = &bind_group_layouts,
    }));
    defer pipeline_layout.release();

    const primitive_pipeline_state = gpu.PrimitiveState{
        .topology = .triangle_strip,
        //.front_face = .ccw,
        //.cull_mode = .back,
    };

    const render_pipeline = device.createRenderPipeline(&gpu.RenderPipeline.Descriptor{
        .label = label,
        .fragment = &fragment,
        .layout = pipeline_layout,
        .primitive = primitive_pipeline_state,
        .vertex = gpu.VertexState{
            .module = shader_module,
            .entry_point = "vertMain",
        },
    });

    const built = BuiltPipeline{ .render = render_pipeline, .bind_group = bind_group, .uniforms = uniforms, .transforms = transforms, .positions = positions, .sizes = sizes, .uint_params = uint_params, .float_params = float_params };
    try self.set(pipeline_id, .built, built);
    try self.set(pipeline_id, .num_shapes, 0);
}
fn preRender(self: *Mod, core: *mach.Core.Mod, entities: *mach.Entities.Mod) !void {
    const label = @tagName(name) ++ ".preRender";
    const encoder = core.state().device.createCommandEncoder(&.{ .label = label });
    defer encoder.release();

    {
        var q = try entities.query(.{
            .ids = mach.Entities.Mod.read(.id),
            .built_pipelines = Mod.read(.built),
        });
        while (q.next()) |v| {
            for (v.ids, v.built_pipelines) |id, built| {
                const view_projection = self.get(id, .view_projection) orelse blk: {
                    const width_px: f32 = @floatFromInt(core.state().size().width);
                    const height_px: f32 = @floatFromInt(core.state().size().height);
                    break :blk math.Mat4x4.projection2D(.{
                        .left = -width_px / 2,
                        .right = width_px / 2,
                        .bottom = -height_px / 2,
                        .top = height_px / 2,
                        .near = -0.1,
                        .far = 100000,
                    });
                };

                // Update uniform buffer
                const uniforms = Uniforms{
                    .view_projection = view_projection,
                };
                encoder.writeBuffer(built.uniforms, 0, &[_]Uniforms{uniforms});
            }
        }
    }

    {
        var q = try entities.query(.{
            .ids = mach.Entities.Mod.read(.id),
            .built_pipelines = Mod.read(.built_triangle),
        });
        while (q.next()) |v| {
            for (v.ids, v.built_pipelines) |id, built| {
                const view_projection = self.get(id, .view_projection) orelse blk: {
                    const width_px: f32 = @floatFromInt(core.state().size().width);
                    const height_px: f32 = @floatFromInt(core.state().size().height);
                    break :blk math.Mat4x4.projection2D(.{
                        .left = -width_px / 2,
                        .right = width_px / 2,
                        .bottom = -height_px / 2,
                        .top = height_px / 2,
                        .near = -0.1,
                        .far = 100000,
                    });
                };

                // Update uniform buffer
                const uniforms = Uniforms{
                    .view_projection = view_projection,
                };
                encoder.writeBuffer(built.uniforms, 0, &[_]Uniforms{uniforms});
            }
        }
    }

    var command = encoder.finish(&.{ .label = label });
    defer command.release();
    core.state().queue.submit(&[_]*gpu.CommandBuffer{command});
}

fn render(self: *Mod, entities: *mach.Entities.Mod) !void {
    const render_pass = if (self.state().render_pass) |rp| rp else std.debug.panic("shapes.state().render_pass must be specified", .{});
    self.state().render_pass = null;

    // Render triangles
    {
        var q = try entities.query(.{
            .ids = mach.Entities.Mod.read(.id),
            .built_pipelines = Mod.read(.built_triangle),
        });
        while (q.next()) |v| {
            for (v.ids, v.built_pipelines) |pipeline_id, built| {
                // Draw the triangles
                const num_shapes = self.get(pipeline_id, .num_shapes).? * 3;
                render_pass.setPipeline(built.render);
                render_pass.setVertexBuffer(0, built.vertices, 0, num_shapes * 3 * (4 * 4 + 4 * 4));
                render_pass.setBindGroup(0, built.bind_group, &.{});
                render_pass.draw(num_shapes, 1, 0, 0);
            }
        }
    }
    // Render shapes
    {
        var q = try entities.query(.{
            .ids = mach.Entities.Mod.read(.id),
            .built_pipelines = Mod.read(.built),
        });
        while (q.next()) |v| {
            for (v.ids, v.built_pipelines) |pipeline_id, built| {
                // Draw the shapes
                const num_shapes = self.get(pipeline_id, .num_shapes).?;
                render_pass.setPipeline(built.render);
                render_pass.setBindGroup(0, built.bind_group, &.{});
                render_pass.draw(4, num_shapes, 0, 0);
            }
        }
    }
}

/// Named colors using the HTML color names
/// Reference: https://htmlcolorcodes.com/color-names/
const NamedColor = enum(u32) {
    // Red
    IndianRed = 0xCD5C5C,
    LightCoral = 0xF08080,
    Salmon = 0xFA8072,
    DarkSalmon = 0xE9967A,
    LightSalmon = 0xFFA07A,
    Crimson = 0xDC143C,
    Red = 0xFF0000,
    FireBrick = 0xB22222,
    DarkRed = 0x8B0000,

    // Pink
    Pink = 0xFFC0CB,
    LightPink = 0xFFB6C1,
    HotPink = 0xFF69B4,
    DeepPink = 0xFF1493,
    MediumVioletRed = 0xC71585,
    PaleVioletRed = 0xDB7093,

    // Orange
    Coral = 0xFF7F50,
    Tomato = 0xFF6347,
    OrangeRed = 0xFF4500,
    DarkOrange = 0xFF8C00,
    Orange = 0xFFA500,

    // Yellow
    Gold = 0xFFD700,
    Yellow = 0xFFFF00,
    LightYellow = 0xFFFFE0,
    LemonChiffon = 0xFFFACD,
    LightGoldenrodYellow = 0xFAFAD2,
    PapayaWhip = 0xFFEFD5,
    Moccasin = 0xFFE4B5,
    PeachPuff = 0xFFDAB9,
    PaleGoldenrod = 0xEEE8AA,
    Khaki = 0xF0E68C,
    DarkKhaki = 0xBDB76B,

    // Purple
    Lavender = 0xE6E6FA,
    Thistle = 0xD8BFD8,
    Plum = 0xDDA0DD,
    Violet = 0xEE82EE,
    Orchid = 0xDA70D6,
    //Fuchsia = 0xFF00FF,
    Magenta = 0xFF00FF,
    MediumOrchid = 0xBA55D3,
    MediumPurple = 0x9370DB,
    RebeccaPurple = 0x663399,
    BlueViolet = 0x8A2BE2,
    DarkViolet = 0x9400D3,
    DarkOrchid = 0x9932CC,
    DarkMagenta = 0x8B008B,
    Purple = 0x800080,
    Indigo = 0x4B0082,
    SlateBlue = 0x6A5ACD,
    DarkSlateBlue = 0x483D8B,

    // Green
    GreenYellow = 0xADFF2F,
    Chartreuse = 0x7FFF00,
    LawnGreen = 0x7CFC00,
    Lime = 0x00FF00,
    LimeGreen = 0x32CD32,
    PaleGreen = 0x98FB98,
    LightGreen = 0x90EE90,
    MediumSpringGreen = 0x00FA9A,
    SpringGreen = 0x00FF7F,
    MediumSeaGreen = 0x3CB371,
    SeaGreen = 0x2E8B57,
    ForestGreen = 0x228B22,
    Green = 0x008000,
    DarkGreen = 0x006400,
    YellowGreen = 0x9ACD32,
    OliveDrab = 0x6B8E23,
    Olive = 0x808000,
    DarkOliveGreen = 0x556B2F,
    MediumAquamarine = 0x66CDAA,
    DarkSeaGreen = 0x8FBC8B,
    LightSeaGreen = 0x20B2AA,
    DarkCyan = 0x008B8B,
    Teal = 0x008080,

    // Blue
    //Aqua = 0x00FFFF,
    Cyan = 0x00FFFF,
    LightCyan = 0xE0FFFF,
    PaleTurquoise = 0xAFEEEE,
    Aquamarine = 0x7FFFD4,
    Turquoise = 0x40E0D0,
    MediumTurquoise = 0x48D1CC,
    DarkTurquoise = 0x00CED1,
    CadetBlue = 0x5F9EA0,
    SteelBlue = 0x4682B4,
    LightSteelBlue = 0xB0C4DE,
    PowderBlue = 0xB0E0E6,
    LightBlue = 0xADD8E6,
    SkyBlue = 0x87CEEB,
    LightSkyBlue = 0x87CEFA,
    DeepSkyBlue = 0x00BFFF,
    DodgerBlue = 0x1E90FF,
    CornFlowerBlue = 0x6495ED,
    MediumSlateBlue = 0x7B68EE,
    RoyalBlue = 0x4169E1,
    Blue = 0x0000FF,
    MediumBlue = 0x0000CD,
    DarkBlue = 0x00008B,
    Navy = 0x000080,
    MidnightBlue = 0x191970,

    // Brown
    CornSilk = 0xFFF8DC,
    BlanchedAlmond = 0xFFEBCD,
    Bisque = 0xFFE4C4,
    NavajoWhite = 0xFFDEAD,
    Wheat = 0xF5DEB3,
    Burlywood = 0xDEB887,
    Tan = 0xD2B48C,
    RosyBrown = 0xBC8F8F,
    SandyBrown = 0xF4A460,
    GoldenRod = 0xDAA520,
    DarkGoldenRod = 0xB8860B,
    Peru = 0xCD853F,
    Chocolate = 0xD2691E,
    SaddleBrown = 0x8B4513,
    Sienna = 0xA0522D,
    Brown = 0xA52A2A,
    Maroon = 0x800000,

    // White
    White = 0xFFFFFF,
    Snow = 0xFFFAFA,
    HoneyDew = 0xF0FFF0,
    MintCream = 0xF5FFFA,
    Azure = 0xF0FFFF,
    AliceBlue = 0xF0F8FF,
    GhostWhite = 0xF8F8FF,
    WhiteSmoke = 0xF5F5F5,
    SeaShell = 0xFFF5EE,
    Beige = 0xF5F5DC,
    OldLace = 0xFDF5E6,
    FloralWhite = 0xFFFAF0,
    Ivory = 0xFFFFF0,
    AntiqueWhite = 0xFAEBD7,
    Linen = 0xFAF0E6,
    LavenderBlush = 0xFFF0F5,
    MistyRose = 0xFFE4E1,

    // Gray
    Gainsboro = 0xDCDCDC,
    LightGrey = 0xD3D3D3,
    Silver = 0xC0C0C0,
    DarkGrey = 0xA9A9A9,
    Gray = 0x808080,
    DimGray = 0x696969,
    LightSlateGray = 0x778899,
    SlateGray = 0x708090,
    DarkSlateGray = 0x2F4F4F,
    Black = 0x000000,
};
