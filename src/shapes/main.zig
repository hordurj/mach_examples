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

// Function interface
pub fn drawRect(
    entities: *mach.Entities.Mod, 
    shapes: *Mod, 
    canvas: mach.EntityID, 
    x: f32, 
    y: f32, 
    width: f32, 
    height: f32,
    color: Vec4
) !mach.EntityID {
    const rect = try entities.new();
    try shapes.set(rect, .pipeline, canvas); 
    try shapes.set(rect, .transform, Mat4x4.translate(vec3(0.0, 0.0, 0.0)));
    try shapes.set(rect, .color, color);
    try shapes.set(rect, .rectangle, 
        .{ 
            .center = vec2(x, y),
            .size = vec2(width, height)
        }
    );
    return rect;
}

pub fn drawCircle(
    entities: *mach.Entities.Mod, 
    shapes: *Mod, 
    canvas: mach.EntityID, 
    x: f32, 
    y: f32, 
    width: f32, 
    height: f32,
    color: Vec4
) !mach.EntityID {
    const circle = try entities.new();
    try shapes.set(circle, .pipeline, canvas); 
    try shapes.set(circle, .transform, Mat4x4.translate(vec3(0.0, 0.0, 0.0)));
    try shapes.set(circle, .color, color);
    try shapes.set(circle, .circle, 
        .{ 
            .center = vec2(x, y),
            .size = vec2(width, height)
        }
    );
    return circle;
}

pub fn drawLine(
    entities: *mach.Entities.Mod, 
    shapes: *Mod, 
    canvas: mach.EntityID, 
    x0: f32, 
    y0: f32, 
    x1: f32,
    y1: f32,
    width: f32,
    color: Vec4
) !mach.EntityID {
    const line = try entities.new();
    try shapes.set(line, .pipeline, canvas); 
    try shapes.set(line, .transform, Mat4x4.translate(vec3(0.0, 0.0, 0.0)));
    try shapes.set(line, .color, color);
    try shapes.set(line, .line, 
        .{ 
            .start = vec2(x0, y0),
            .finish = vec2(x1, y1),
            .width = width
        }
    );
    return line;
}

// drawTriangle
// drawPolygon

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
    width: f32,
};

pub const Color = struct {
    color: Vec4,
};

pub const components = .{
    .view_projection = .{ .type = math.Mat4x4, .description = ""},
    .transform = .{ .type = Mat4x4, .description = "Shape transformation"},
    .shader = .{ .type = *gpu.ShaderModule, .description = ""},
    .blend_state = .{ .type = gpu.BlendState, .description = ""},
    .bind_group_layout = .{ .type = *gpu.BindGroupLayout, .description = ""},
    .bind_group = .{ .type = *gpu.BindGroup, .description = ""},
    .color_target_state = .{ .type = gpu.ColorTargetState, .description = ""},
    .fragment_state = .{ .type = gpu.FragmentState, .description = ""},
    .layout = .{ .type = *gpu.PipelineLayout, .description = ""},
    .num_shapes = .{ .type = u32, .description = ""},

    .shapes_pipeline = .{ .type = void },
    .rectangle = .{ .type = Rectangle },
    .color = .{ .type = Vec4 },
    .line = .{ .type = Line },
//    .triangle =
//    .path
//    .quadratic   .cubic
    .circle = .{ .type = Circle },
    .pipeline = .{ .type = mach.EntityID },
    .built = .{ .type = BuiltPipeline, .description = "internal" },

};

const Uniforms = extern struct {
    // WebGPU requires that the size of struct fields are multiples of 16
    // So we use align(16) and 'extern' to maintain field order

    /// The view * orthographic projection matrix
    view_projection: math.Mat4x4 align(16),
};

const Params = extern struct {
    param1: math.Vec4,
    param2: math.Vec4,
};
const shape_buffer_cap = 10000;
pub var cp_transforms: [shape_buffer_cap]math.Mat4x4 = undefined;
pub var cp_uv_transforms: [shape_buffer_cap]math.Mat4x4 = undefined;
pub var cp_center: [shape_buffer_cap]math.Vec2 = undefined;
pub var cp_size: [shape_buffer_cap]math.Vec2 = undefined;
pub var cp_color: [shape_buffer_cap]math.Vec4 = undefined;
pub var cp_params: [shape_buffer_cap]Params = undefined;

pub const BuiltPipeline = struct {
    render: *gpu.RenderPipeline,
    bind_group: *gpu.BindGroup,
    uniforms: *gpu.Buffer,
    transforms: *gpu.Buffer,
    positions: *gpu.Buffer,
    sizes: *gpu.Buffer,
    colors: *gpu.Buffer,
    params: *gpu.Buffer,

    pub fn deinit(p: *const BuiltPipeline) void {
        p.render.release();
        p.bind_group.release();
        p.uniforms.release();
        p.transforms.release();
        p.positions.release();
        p.sizes.release();
        p.colors.release();
        p.params.release();
    }
};


fn init(self: *Mod) void {
    std.debug.print("Shapes init\n", .{});
    const allocator = gpa.allocator();

    self.init(.{
        .allocator = allocator,
    });
}

fn deinit(
    self: *Mod,
    entities: *mach.Entities.Mod
) !void {
    std.debug.print("Shapes deinit\n", .{});
    _ = self;

    var q = try entities.query(.{
        .built_pipelines = Mod.read(.built),
    });
    while (q.next()) |v| {
        for (v.built_pipelines) |built| {
            built.deinit();
        }
    }
}

fn updateShapes(
    self: *Mod,
    entities: *mach.Entities.Mod, 
    core: *mach.Core.Mod, 
) !void {
    _ = self;

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
                    .colors = Mod.read(.color)
                });
                while (sq.next()) |w| {
                    for (w.ids, w.shape_pipelines, w.transforms, w.rectangles, w.colors) |shape_id, shape_pipeline_id, transform, rectangle, color| {
                        _ = shape_id;
                        if (pipeline_id == shape_pipeline_id) {
                            cp_transforms[num_shapes.*] = transform;
                            cp_center[num_shapes.*] = rectangle.center;
                            cp_size[num_shapes.*] = rectangle.size;
                            cp_color[num_shapes.*] = color;                        
                            cp_params[num_shapes.*] = 
                            .{
                                .param1 = vec4(1.0, 0.0, 0.0, 0.0), 
                                .param2 = vec4(0.8, 1.0, 1.0, 1.0)
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
                    .colors = Mod.read(.color)
                });
                while (sq.next()) |w| {
                    for (w.ids, w.shape_pipelines, w.transforms, w.circles, w.colors) |shape_id, shape_pipeline_id, transform, circle, color| {
                        _ = shape_id;
                        if (pipeline_id == shape_pipeline_id) {
                            cp_transforms[num_shapes.*] = transform;
                            cp_center[num_shapes.*] =  circle.center;
                            cp_size[num_shapes.*] = circle.size;
                            cp_color[num_shapes.*] = color;                        
                            cp_params[num_shapes.*] = 
                            .{
                                .param1 = vec4(2.0, 0.0, 0.0, 0.0), 
                                .param2 = vec4(0.0, 0.0, 0.0, 0.0)
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
                    .colors = Mod.read(.color)
                });
                while (sq.next()) |w| {
                    for (w.ids, w.shape_pipelines, w.transforms, w.lines, w.colors) |shape_id, shape_pipeline_id, transform, line, color| {
                        _ = shape_id;
                        if (pipeline_id == shape_pipeline_id) {
                            cp_transforms[num_shapes.*] = transform;
                            cp_center[num_shapes.*] =  line.start;
                            cp_size[num_shapes.*] = line.finish;
                            cp_color[num_shapes.*] = color;                        
                            cp_params[num_shapes.*] =                             
                            .{
                                .param1 = vec4(3.0, line.width, 0.0, 0.0), 
                                .param2 = vec4(0.0, 0.0, 0.0, 0.0)
                            };          
                            num_shapes.* += 1;
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
                encoder.writeBuffer(built.colors, 0, cp_color[0..num_shapes.*]);
                encoder.writeBuffer(built.params, 0, cp_params[0..num_shapes.*]);

                var command = encoder.finish(&.{ .label = label });  // Encoder leaks if finish not called
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

    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .shape_pipelines = Mod.read(.shapes_pipeline),
    });
    while (q.next()) |v| {
        for (v.ids) |pipeline_id| {
            try buildPipeline(self, core, pipeline_id);
        }
    }
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

    const colors = device.createBuffer(&.{
        .label = label ++ " colors",
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf(math.Vec4) * shape_buffer_cap,
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

    const params = device.createBuffer(&.{
        .label = label ++ " params",
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf(Params) * shape_buffer_cap,
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
                gpu.BindGroup.Entry.buffer(4, colors, 0, @sizeOf(math.Vec4) * shape_buffer_cap, @sizeOf(math.Vec4)),
                gpu.BindGroup.Entry.buffer(5, params, 0, @sizeOf(Params) * shape_buffer_cap, @sizeOf(Params)),
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

    const built = BuiltPipeline{
        .render = render_pipeline,
        .bind_group = bind_group,
        .uniforms = uniforms,
        .transforms = transforms,
        .positions = positions,
        .sizes = sizes,
        .colors = colors,
        .params = params
    };
    std.debug.print("Built pipeline {}\n", .{pipeline_id});
    try self.set(pipeline_id, .built, built);
    try self.set(pipeline_id, .num_shapes, 0);
}
fn preRender(
    self: *Mod,
    core: *mach.Core.Mod,
    entities: *mach.Entities.Mod
) !void {
    const label = @tagName(name) ++ ".preRender";
    const encoder = core.state().device.createCommandEncoder(&.{ .label = label });
    defer encoder.release();

    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .built_pipelines = Mod.read(.built),
    });
    while (q.next()) |v| {
        for (v.ids, v.built_pipelines) |id, built| {
            const view_projection = self.get(id, .view_projection) orelse blk: {
                const width_px: f32 = @floatFromInt(mach.core.size().width);
                const height_px: f32 = @floatFromInt(mach.core.size().height);
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

    var command = encoder.finish(&.{ .label = label });
    defer command.release();
    core.state().queue.submit(&[_]*gpu.CommandBuffer{command});    
}

fn render(
    self: *Mod,
    entities: *mach.Entities.Mod
) !void {
    const render_pass = if (self.state().render_pass) |rp| rp else std.debug.panic("shapes.state().render_pass must be specified", .{});
    self.state().render_pass = null;
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