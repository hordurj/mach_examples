// An application module to demonstrated the math.collision library
//

const std = @import("std");
const mach = @import("mach");
const math = mach.math;
const vec2 = math.vec2;
const Vec2 = math.Vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Vec4 = math.Vec4;
const Mat4x4 = math.Mat4x4;
const collision = math.collision;
const gpu = mach.gpu;

const cex = @import("collision_ex");
const ColliderType = cex.ColliderType;
const Collider = cex.Collider;
const collides = cex.collides;

const util = @import("../util.zig");
const shp = @import("../shapes/main.zig");
const renderer = @import("../renderer/main.zig");
const Canvas = shp.Canvas;
const LineStyle = shp.LineStyle;
const FillStyle = shp.FillStyle;
const drawCircle = shp.drawCircle;
const drawLine = shp.drawLine;
const drawRect = shp.drawRect;
const drawTriangle = shp.drawTriangle;
const drawPolygon = shp.drawPolygon;
const col = shp.col;
const rgb = shp.rgb;

var gpa = std.heap.GeneralPurposeAllocator(.{.verbose_log = false}){};
pub const name = .app; // The main app has to be named .app
pub const Mod = mach.Mod(@This());

//**************************************
// Module state
//**************************************

// App state

// Resources
allocator: std.mem.Allocator,
frame_encoder: *gpu.CommandEncoder = undefined,
frame_render_pass: *gpu.RenderPassEncoder = undefined,
shapes_canvas: mach.EntityID = undefined,
triangle_canvas: mach.EntityID = undefined,
selected_object: ?mach.EntityID = null,         // One object can be selected
selected_pick_point: Vec2 = vec2(0.0, 0.0),     // Pick location relative to object position.
dragging: bool = false,
default_styles: Styles = undefined,
polygon_styles: Styles = undefined,
scene_update_required: bool = false,
vertex_allocations: std.ArrayList([]Vec2),

//**************************************
// Components
//**************************************

pub const components = .{
    .position = .{ .type = Vec2 },
    .collider = .{ .type = Collider },
    .selected_style = .{ .type = Style },
    .hover_style = .{ .type = Style },
    .default_style = .{ .type = Style },
    .marker = .{ .type = void },
};

const Style = struct {
    line_style: shp.LineStyle,
    fill_style: shp.FillStyle
};

const Styles = struct {
    selected_style: Style,
    hover_style: Style,
    default_style: Style,
};

//**************************************
// Internal app member functions
//**************************************
fn allocateVertices2(self: *@This(), n: usize) ![]Vec2 {
    const vertices = try self.allocator.alloc(Vec2, n);
    try self.vertex_allocations.append(vertices);
    return vertices;
}

fn freeVertices2(self: *@This()) void {
    for (self.vertex_allocations.items) |v| {
        self.allocator.free(v);
    }
    self.vertex_allocations.deinit();
}

//**************************************
// Systems
//**************************************

pub const systems = .{
    .init = .{ .handler = init },
    .deinit = .{ .handler = deinit },
    .after_init = .{ .handler = afterInit },
    .update = .{ .handler = update },
    .input = .{ .handler = input },
    .render = .{ .handler = render },
    .end_frame = .{ .handler = endFrame },
};

fn init(
    self: *Mod,
    core: *mach.Core.Mod,
    renderer_mod: *renderer.Mod,
    shapes: *shp.Mod,
) !void {
    _ = core;
    shapes.schedule(.init);
    renderer_mod.schedule(.init);
    self.schedule(.after_init);
}
fn deinit(
    self: *Mod,
    shapes: *shp.Mod,
) !void {
    shapes.schedule(.deinit);
    self.state().freeVertices2();
    _ = gpa.deinit();
}

fn afterInit(
    self: *Mod,
    entities: *mach.Entities.Mod,
    shapes: *shp.Mod,
) !void {
    const allocator = gpa.allocator();

    const shapes_canvas = try entities.new();
    try shapes.set(shapes_canvas, .shapes_pipeline, {});
    try shapes.set(shapes_canvas, .pipeline, shapes_canvas);

    const triangle_canvas = try entities.new();
    try shapes.set(triangle_canvas, .shapes_pipeline, {});
    try shapes.set(triangle_canvas, .triangle_pipeline, triangle_canvas);

    shapes.schedule(.update);

    const default_styles = Styles{
        .hover_style = .{
            .line_style = .{ .color = col(.Red), .width = 8.0 },
            .fill_style = .{ .color = vec4(0.0, 0.0, 0.0, 0.0) },
        },
        .selected_style = .{
            .line_style = .{ .color = col(.Yellow), .width = 8.0 },
            .fill_style = .{ .color = vec4(0.0, 0.0, 0.0, 0.0) },
        },
        .default_style = .{
            .line_style = .{ .color = col(.White), .width = 8.0 },
            .fill_style = .{ .color = vec4(0.0, 0.0, 0.0, 0.0) },
        },
    };

    const polygon_styles = Styles{
        .hover_style = .{
            .line_style = .{ .color = col(.Red), .width = 2.0 },
            .fill_style = .{ .color = vec4(0.0, 0.0, 0.0, 0.0) },
        },
        .selected_style = .{
            .line_style = .{ .color = col(.Yellow), .width = 2.0 },
            .fill_style = .{ .color = vec4(0.0, 0.0, 0.0, 0.0) },
        },
        .default_style = .{
            .line_style = .{ .color = col(.White), .width = 2.0 },
            .fill_style = .{ .color = vec4(0.0, 0.0, 0.0, 0.0) },
        },
    };

    self.init(.{
        .allocator = allocator,
        .shapes_canvas = shapes_canvas,
        .triangle_canvas = triangle_canvas,
        .default_styles = default_styles,
        .polygon_styles = polygon_styles,
        .vertex_allocations = std.ArrayList([]Vec2).init(allocator)
    });

    shapes.schedule(.update_shapes);
}
fn update(
    self: *Mod,
    entities: *mach.Entities.Mod,
    core: *mach.Core.Mod,
    renderer_mod: *renderer.Mod,
) !void {
    if (core.state().should_close) {
        return;
    }
    _ = entities;
    self.schedule(.input);
    renderer_mod.schedule(.begin_frame);
    self.schedule(.render);
}
fn input(self: *Mod, core: *mach.Core.Mod, entities: *mach.Entities.Mod, shapes: *shp.Mod) !void {
    const style = self.state().default_styles;
    var canvas = Canvas{
        .entities = entities,
        .shapes = shapes,
        .canvas = self.state().shapes_canvas,
        .line_style = style.default_style.line_style,
        .fill_style = style.default_style.fill_style
    };
    var triangle_canvas = Canvas{
        .entities = entities,
        .shapes = shapes,
        .canvas = self.state().triangle_canvas,
        .line_style = style.default_style.line_style,
        .fill_style = .{.color = col(.Aquamarine)}, //style.default_style.fill_style
    };
    const mouse_pos = core.state().mousePosition();
    const pos = util.windowToCanvas(core, mouse_pos);

    var iter = core.state().pollEvents();
    // Handle inputs
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .escape, .q => core.schedule(.exit),
                    .f11 => {
                        if (core.state().displayMode() != .fullscreen) {
                            core.state().setDisplayMode(.fullscreen);
                        } else {
                            core.state().setDisplayMode(.windowed);
                        }
                    },
                    .c => {
                        // Create circle at mouse location.
                        canvas.line_style = style.default_style.line_style;
                        canvas.fill_style = style.default_style.fill_style;
                        _ = try createCircle(self, &canvas, pos, 50.0);

                        self.state().scene_update_required = true;
                    },
                    .r => {
                        // Create circle at mouse location.
                        canvas.line_style = style.default_style.line_style;
                        canvas.fill_style = style.default_style.fill_style;
                        _ = try createRectangle(self, &canvas, pos, vec2(150.0, 100.0));

                        self.state().scene_update_required = true;
                    },
                    .l => {
                        // draw line
                        canvas.line_style = style.default_style.line_style;
                        canvas.fill_style = style.default_style.fill_style;
                        // TODO: place at mouse pos
                        _ = try createLine(self, &canvas, vec2(-400.0, -200.0), vec2(-200.0, -50.0));

                        self.state().scene_update_required = true;
                    },
                    .t => {
                        // draw triangle                        
                        // TODO: place at mouse pos
                        const triangle = try createTriangle(self, &triangle_canvas, 
                            vec2(-100.0, -200.0),
                            vec2(100.0, -200.0),
                            vec2(0.0, -50.0));
                        try self.set(triangle, .hover_style, .{
                            .line_style = .{ .color = col(.Red), .width = 8},
                            .fill_style = .{ .color = col(.Orange)},    
                        });
                        try self.set(triangle, .selected_style, .{
                            .line_style = .{ .color = col(.Red), .width = 8},
                            .fill_style = .{ .color = col(.Yellow)},    
                        });

                        self.state().scene_update_required = true;
                    },
                    .p => {
                        // draw polygon
                        // TODO: place at mouse pos
                        var vertices = try self.state().allocateVertices2(5);
                        vertices[0] = vec2(200.0, -200.0);
                        vertices[1] = vec2(400.0, -200.0);
                        vertices[2] = vec2(350.0, -50.0);
//                        vertices[3] = vec2(300.0, -100.0);   // makes the polygon concave
                        vertices[3] = vec2(300.0, -15.0);
                        vertices[4] = vec2(250.0, -50.0);
                        canvas.line_style = self.state().polygon_styles.default_style.line_style;
                        canvas.fill_style = self.state().polygon_styles.default_style.fill_style;
                        _ = try createPolygon(self, &canvas, vertices);

                        self.state().scene_update_required = true;
                    },
                    else => {},
                }
            },
            .mouse_press => |_| {
                // Check if any object is selected
                const selected_object = findObjectSelection(entities, pos);
                if (selected_object) |obj_id| {
                    self.state().selected_object = selected_object;
                    if (self.get(obj_id, .position)) |position| {
                        self.state().selected_pick_point = pos.sub(&position);
                    }
                    self.state().scene_update_required = true;
                }
            },
            .mouse_release => |_| {
                self.state().selected_object = null;
                self.state().scene_update_required = true;
            },
            .mouse_motion => |ev| {
                // if left mouse button down or in drag mode and an object selected, move object
                const mpos = util.windowToCanvas(core, ev.pos);
                if (self.state().selected_object) |obj_id| {
                    try self.set(obj_id, .position, mpos.sub(&self.state().selected_pick_point));
                    self.state().scene_update_required = true;
                }
                // TODO: check if hover state changes - enter / exit
            },
            .close => core.schedule(.exit),
            else => {},
        }
    }
}

const CollisionReport = struct {
    id_a: mach.EntityID = undefined,
    id_b: mach.EntityID = undefined,
    normal: Vec2 = undefined,
    depth: f32 = undefined,
    contact_point_1_on_a: ?Vec2 = null,
    contact_point_2_on_a: ?Vec2 = null,
//    contact_point_1_on_b: ?Vec2,
//    contact_point_2_on_b: ?Vec2,
};

// circlecircle
// circlepolygon
// polygonpolygon

fn circlePolygonCollisionReport(circle_a: *const collision.Circle, polygon_b: []Vec2) CollisionReport {
    var normal = vec2(0.0, 0.0);
    var depth: f32 = 0.0;
    var cp1_a: ?Vec2 = null;
    const cp2_a: ?Vec2 = null;

    var v0 = polygon_b[polygon_b.len-1];
    var min_result = struct {
        n: Vec2,
        d: f32,
        i: usize
    }{
        .n = vec2(0.0, 0.0),
        .d = std.math.floatMax(f32),
        .i = undefined
    };
    var closest_vertex = struct {
        v: Vec2 = undefined,
        d: f32 = std.math.floatMax(f32),
        i: usize = undefined,
    }{};

    for (polygon_b[0..], 0..) |v1, i| {
        const edge = v1.sub(&v0);
        const n = vec2(edge.y(), -edge.x()).normalize(0.0); 
        const vc = circle_a.pos.sub(&v0);
        const d = vc.dot(&n);
        if (vc.len() < closest_vertex.d) {
            closest_vertex.v = v0;
            closest_vertex.d = vc.len();
            closest_vertex.i = i;
        }
        std.debug.print("Check vertex: idx {}: vc.len: {d:.1}  d: {d:.1}\n", .{i, vc.len(), d});

        v0 = v1;
        if (d > circle_a.radius) {
            // Circle does not collide with this edge
            std.debug.print("No intersection\n", .{});
            return .{};
//            continue;
        }

        const current_depth = circle_a.radius - d;
        if (current_depth < min_result.d) {
            min_result.d = current_depth;
            min_result.n = n;
            min_result.i = i;
        }
    }

    // Check circle to closest point axis
    //is_overlap: 
    {
        v0 = closest_vertex.v;
        const n = circle_a.pos.sub(&v0).normalize(0.0); 
        const minmax_b = cex.minmaxProjectionDistance(n, v0, polygon_b);                        
        
        // Circle projects to +- radius
        const vc = circle_a.pos.sub(&v0);
        const d = vc.dot(&n);
        const minmax_a = vec2(d - circle_a.radius, d + circle_a.radius);

        if ((minmax_a.x() > minmax_b.y()) or (minmax_a.y() < minmax_b.x())) {

            std.debug.print("Vertex - No intersection\n", .{});
            return .{};
            //break :is_overlap;
        }

        const current_depth = @min(minmax_a.y() - minmax_b.x(), minmax_b.y() - minmax_a.x());
        std.debug.print("Vertex: {} - d: {d:.1} radius: {d:.1} Current depth: {d:.1}  min_depth: {d:.1} n: {d:.1}, {d:.1} i: {} \n", 
            .{closest_vertex.i, d, circle_a.radius, current_depth, min_result.d, min_result.n.x(), min_result.n.y(), min_result.i});

        if (current_depth <= min_result.d) {
            std.debug.print("Use vertex: depth: {d:.1} normal: [{d:.1} {d:.1}]\n", .{current_depth, n.x(), n.y()});
            min_result.d = current_depth;
            min_result.n = n; //n.mulScalar(-1.0);
        }
    }

    depth = -min_result.d;
    normal = min_result.n.mulScalar(-1.0);  
    cp1_a = circle_a.pos.add(&normal.mulScalar(circle_a.radius)); 

    return CollisionReport{
        .id_a = undefined,
        .id_b = undefined,
        .normal = normal,
        .depth = depth,
        .contact_point_1_on_a = cp1_a,
        .contact_point_2_on_a = cp2_a,
//        .contact_point_1_on_b = cp1_b,
//        .contact_point_2_on_b = cp2_b,
    };
}

pub fn minAndVertexProjectionDistance(n: Vec2, v0: Vec2, v: []const Vec2) struct {f32, Vec2} {
    var min_d = n.dot(&v[0].sub(&v0));
    var min_v = v[0];
    for (v[1..]) |vb| {
        const d = n.dot(&vb.sub(&v0));
        if (d < min_d) {
            min_d = d;
            min_v = vb;
        }
    }
    return .{min_d, min_v};
}

fn polygonCollisionReport(polygon_a: []Vec2, polygon_b: []Vec2) CollisionReport {
    var normal = vec2(0.0, 0.0);
    var depth: f32 = 0.0;
    var cp1_a: ?Vec2 = null;
    const cp2_a: ?Vec2 = null;

    var v0 = polygon_b[polygon_b.len-1];
    var min_result = struct {
        n: Vec2,
        v: Vec2,
        d: f32,
        i: usize,
        a: bool
    }{
        .n = vec2(0.0, 0.0),
        .d = std.math.floatMax(f32),
        .i = undefined,
        .v = vec2(0.0, 0.0),
        .a = false,
    };

    for (polygon_b[0..], 0..) |v1, i| {
        const edge = v1.sub(&v0);
        const n = vec2(edge.y(), -edge.x()).normalize(0.0); 
        const min_a_v = minAndVertexProjectionDistance(n, v0, polygon_a);
        v0 = v1;

        if (min_a_v[0] > 0.0) {
            // no intersection with this edge
            continue ;
        }

        const current_depth = -min_a_v[0];
        if (current_depth < min_result.d) {
            min_result.d = current_depth;
            min_result.n = n;
            min_result.i = i;
            min_result.v = min_a_v[1];
            min_result.a = true;
        }
    }

    v0 = polygon_a[polygon_a.len-1];
    for (polygon_a[0..], 0..) |v1, i| {
        const edge = v1.sub(&v0);
        const n = vec2(edge.y(), -edge.x()).normalize(0.0); 
        const min_b_v = minAndVertexProjectionDistance(n, v0, polygon_b);
        v0 = v1;

        if (min_b_v[0] > 0.0) {
            // no intersection with this edge
            // continue ;

            return .{};
        }

        const current_depth = -min_b_v[0];
        if (current_depth < min_result.d) {
            min_result.d = current_depth;
            min_result.n = n;
            min_result.i = i;
            min_result.v = min_b_v[1];      
            min_result.a = false;     
        }
    }

    if (min_result.a) {
        depth = min_result.d;
        normal = min_result.n;  
        cp1_a = min_result.v;  
    } else {
        depth = min_result.d;
        normal = min_result.n.mulScalar(-1.0);  
        cp1_a = min_result.v.add(&normal.mulScalar(-depth)); 
    }

    return CollisionReport{
        .id_a = undefined,
        .id_b = undefined,
        .normal = normal,
        .depth = depth,
        .contact_point_1_on_a = cp1_a,
        .contact_point_2_on_a = cp2_a,
    };
}
fn computeCollisionReport(id_a: mach.EntityID, id_b: mach.EntityID, collider_a: *const Collider, collider_b: *const Collider) CollisionReport {
    // Only support circle and polygon

    var normal = vec2(0.0, 0.0);
    var depth: f32 = 0.0;
    var cp1_a: ?Vec2 = null;
    const cp2_a: ?Vec2 = null;
    switch (collider_a.*) {
        .circle => |circle_a| {
            switch (collider_b.*) {
                .circle => |circle_b| {
                    const delta = circle_b.pos.sub(&circle_a.pos);
                    const distance = delta.len();
                    depth = distance - circle_a.radius - circle_b.radius; 
                    if (depth > 0.0) {
                        return .{};
                    }
                    normal = delta.mulScalar(1.0 / distance);
                    cp1_a = circle_a.pos.add(&normal.mulScalar(circle_a.radius));
                },
                .triangle, .polygon => |polygon_b| {
                    std.debug.print("Circle / polygon\n" ,.{});
                    const cr = circlePolygonCollisionReport(&circle_a, polygon_b);
                    depth = cr.depth;
                    normal = cr.normal;  
                    cp1_a = cr.contact_point_1_on_a;  
                },
                else => {}
            }
        },
        .triangle, .polygon => |polygon_a| {
            switch (collider_b.*) {
                .circle => |circle_b| {
                    std.debug.print("Polygon / circle\n" ,.{});

                    const cr = circlePolygonCollisionReport(&circle_b, polygon_a);
                    depth = cr.depth;
                    normal = cr.normal.mulScalar(-1.0);  
                    if (cr.contact_point_1_on_a) |contact_point_1_on_a| {
                        cp1_a = contact_point_1_on_a.add(&normal.mulScalar(-depth));  
                    }
                },
                .triangle, .polygon => |polygon_b| {
                    const cr = polygonCollisionReport(polygon_a, polygon_b);
                    depth = cr.depth;
                    normal = cr.normal;  
                    cp1_a = cr.contact_point_1_on_a;  
                },
                else => {}            
            }
        },
        else => {}
    }

    return CollisionReport{
        .id_a = id_a,
        .id_b = id_b,
        .normal = normal,
        .depth = depth,
        .contact_point_1_on_a = cp1_a,
        .contact_point_2_on_a = cp2_a,
//        .contact_point_1_on_b = cp1_b,
//        .contact_point_2_on_b = cp2_b,
    };
}

fn showCollisionReport(self: *Mod, entities: *mach.Entities.Mod, shapes: *shp.Mod, canvas: *Canvas, collision_report: *const CollisionReport) !void {
    _ = shapes;
    _ = entities;

    // Push style
    const line_style = canvas.line_style;
    const fill_style = canvas.fill_style;

    if (collision_report.contact_point_1_on_a) |cp| {
        // Draw contact point
        canvas.line_style.width = 2;
        const rect_id = try drawRect(canvas, cp.x(), cp.y(), 15.0, 15.0);
        try self.set(rect_id, .marker, {});

        // Draw line between
        canvas.line_style.width = 1;
        canvas.fill_style.color = vec4(0.0, 0.0, 0.0, 0.0);

        const end_point = cp.add(&collision_report.normal.mulScalar(collision_report.depth));
        const line_id = try drawLine(canvas, cp.x(), cp.y(), end_point.x(), end_point.y()); 
        try self.set(line_id, .marker, {});
    }

    // Pop style
    canvas.line_style = line_style;
    canvas.fill_style = fill_style;
} 

fn resolveCollision(pos: Vec2, collision_report: *const CollisionReport) Vec2 {
    std.debug.print("Resolve collision: depth: {d:.1} -- normal: {d:.1} {d:.1}\n", 
        .{collision_report.depth, collision_report.normal.x(), collision_report.normal.y()});
    return pos.add(&collision_report.normal.mulScalar(collision_report.depth));
//fn resolveCollision(id_a: mach.EntityID, id_b: mach.EntityID, collision_report: *const CollisionReport) !void {
//fn computeCollisionReport(id_a: mach.EntityID, id_b: mach.EntityID, collider_a: *const Collider, collider_b: *const Collider) CollisionReport {

}

fn getColliderPosition(collider: *const Collider) Vec2 {
    switch (collider.*) {
        .circle => |circle_collider| { return circle_collider.pos; },
        .rectangle => |rectangle_collider| { return rectangle_collider.pos; },
        .line => |line_collider| { return line_collider.start; },
        .triangle, .polygon => |vertices| { return vertices[0]; },
        else => { return vec2(0.0, 0.0); }
    }
}
fn updateColliderPosition(position: *const Vec2, collider: *Collider) void {
    switch (collider.*) {
        .circle => |*circle_collider| { circle_collider.pos = position.*; },
        .rectangle => |*rectangle_collider| { rectangle_collider.pos = position.*; },
        .line => |*line_collider| { 
            const delta = line_collider.end.sub(&line_collider.start);
            line_collider.start = position.*; 
            line_collider.end = line_collider.start.add(&delta); 
        },
        .triangle, .polygon => |*vertices| {
            const delta = position.sub(&vertices.*[0]);
            for (vertices.*) |*vertex| {
                vertex.* = vertex.add(&delta);
            }
        },
        else => {}
    }
}
fn render(
    self: *Mod,
    core: *mach.Core.Mod,
    entities: *mach.Entities.Mod,
    shapes: *shp.Mod,
    renderer_mod: *renderer.Mod,
) !void {
    //self.state().scene_update_required = true; // Always update for now.

    if (self.state().scene_update_required) {
        self.state().scene_update_required = false;

        // Clear all marker entitites
        {
            var q = try entities.query(.{
                .ids = mach.Entities.Mod.read(.id),
                .markers = Mod.read(.marker),
            });
            while (q.next()) |v| {
                for (v.ids) |id| {
                    try entities.remove(id);
                }
            }
        }

        const shapes_canvas = self.state().shapes_canvas;
        var canvas = Canvas{
            .entities = entities,
            .shapes = shapes,
            .canvas = shapes_canvas,
            .line_style = self.state().default_styles.hover_style.line_style,
            .fill_style = self.state().default_styles.hover_style.fill_style
        };
        canvas.fill_style.color = col(.Blue);

        // Update
        const mouse_pos = core.state().mousePosition(); //vec2FromPosition(core.state().mousePosition());
        const pos = util.windowToCanvas(core, mouse_pos);
        const point: Collider = .{ .point = math.collision.Point{ .pos = pos }};

        // Update colliders and styles
        {
            var q = try entities.query(.{
                .ids = mach.Entities.Mod.read(.id),
                .positions = Mod.write(.position),
                .colliders = Mod.write(.collider),
                .line_styles = shp.Mod.write(.line_style),
                .fill_styles = shp.Mod.write(.fill_style),
                .default_styles = Mod.read(.default_style),
                .hover_styles = Mod.read(.hover_style),
                .selected_styles = Mod.read(.selected_style),
            });
            while (q.next()) |v| {
                for (v.ids, v.positions, v.colliders, v.line_styles, v.fill_styles, 
                        v.default_styles, v.hover_styles, v.selected_styles) 
                        |obj_id, *position_a, *collider_a, *line_style, *fill_style, 
                        default_style, hover_style, selected_style| 
                {
                    updateColliderPosition(position_a, collider_a);

                    // TODO: only need to change styles if mode is changing (selected, hover, default, ...)
                    if (obj_id == self.state().selected_object) {
                        line_style.* = selected_style.line_style;
                        fill_style.* = selected_style.fill_style;
                    }
                    if (collides(&point, collider_a)) {
                        line_style.* = hover_style.line_style;
                        fill_style.* = hover_style.fill_style;
                    } else {
                        line_style.* = default_style.line_style;
                        fill_style.* = default_style.fill_style;
                    }

                    // Check if object collides with another collider
                    var q2 = try entities.query(.{
                        .ids = mach.Entities.Mod.read(.id),
                        .positions = Mod.write(.position),
                        .colliders = Mod.write(.collider),
                    });
                    var collision_detected = false;
                    while (q2.next()) |v2| {
                        for (v2.ids, v2.positions, v2.colliders) |id_b, *position_b, *collider_b| {
                            if (obj_id != id_b and self.state().selected_object != id_b and collides(collider_a, collider_b)) {
                                collision_detected = true;
                                // Get collision information
                                const collision_report = computeCollisionReport(obj_id, id_b, collider_a, collider_b);

                                // Show collision resolution
                                try showCollisionReport(self, entities, shapes, &canvas,&collision_report);

                                const pos_a = getColliderPosition(collider_a);
                                const pos_b = getColliderPosition(collider_b);

                                std.debug.print("Position A: {d:.1}, {d:.1}  Position B: {d:.1}, {d:.1}\n", .{pos_a.x(), pos_a.y(), pos_b.x(), pos_b.y()});
                                // Resolve collision if enabled
                                if (collision_report.contact_point_1_on_a) |_| {
                                    var cr = collision_report;
                                    if (self.state().selected_object != obj_id) {
                                        cr.depth *= 0.5;
                                        position_a.* = resolveCollision(position_a.*, &cr);
                                        updateColliderPosition(position_a, collider_a);
                                    }
                                    cr.depth *= -1.0;
                                    position_b.* = resolveCollision(position_b.*, &cr);
                                    updateColliderPosition(position_b, collider_b);

                                    self.state().scene_update_required = true;
                                }

                                // Draw overlap if both are rect                                
                                switch (collider_a.*) {
                                    .rectangle => |rect_a| {
                                        switch (collider_b.*) {
                                            .rectangle => |rect_b| {
                                                if (rect_a.collisionRect(rect_b)) |collision_rect| {
                                                    const rect = try (drawRect(&canvas, 
                                                        collision_rect.pos.x() + collision_rect.size.x() / 2.0, 
                                                        collision_rect.pos.y() + collision_rect.size.y() / 2.0, 
                                                        collision_rect.size.x(), 
                                                        collision_rect.size.y())
                                                    );
                                                    try self.set(rect, .marker, {});
                                                }
                                            },
                                            else => {}
                                        }
                                    },
                                    else => {}
                                }
                            }
                        }
                    }
                    if (collision_detected) {
                        //fill_style.*.color = col(.Green);
                        line_style.*.color = col(.Purple);
                    }
                }
            }
        }

        //try updateShapePositions(entities);
        //updateShapePositions(entities: *mach.Entities.Mod);
        // Update circles
        {
            var q = try entities.query(.{
                .positions = Mod.read(.position),
                .circles = shp.Mod.write(.circle),
            });
            while (q.next()) |v| {
                for (v.positions, v.circles) |position, *circle| {
                    circle.center = position;
                }
            }
        }

        // Update rectangles
        {
            var q = try entities.query(.{
                .positions = Mod.read(.position),
                .rectangles = shp.Mod.write(.rectangle),
            });
            while (q.next()) |v| {
                for (v.positions, v.rectangles) |position, *rectangle| {
                    rectangle.center = vec2(
                        position.x() + rectangle.size.x()/2.0,
                        position.y() + rectangle.size.y()/2.0
                    );
                }
            }
        }

        // Update lines
        {
            var q = try entities.query(.{
                .positions = Mod.read(.position),
                .lines = shp.Mod.write(.line),
            });
            while (q.next()) |v| {
                for (v.positions, v.lines) |position, *line| {
                    const delta = line.finish.sub(&line.start);
                    line.*.start = position; 
                    line.*.finish = line.start.add(&delta); 
                }
            }
        }

        // Update triangle
        {
            var q = try entities.query(.{
                .positions = Mod.read(.position),
                .triangles = shp.Mod.write(.triangle),
            });
            while (q.next()) |v| {
                for (v.positions, v.triangles) |position, *triangle| {
                    const newpos = vec4(position.x(), position.y(), 0.0, 1.0);
                    const delta = newpos.sub(&triangle.p0);
                    triangle.p0 = triangle.p0.add(&delta); 
                    triangle.p1 = triangle.p1.add(&delta); 
                    triangle.p2 = triangle.p2.add(&delta); 
                }
            }
        }

        {
            var q = try entities.query(.{
                .positions = Mod.read(.position),
                .paths = shp.Mod.write(.path),
            });
            while (q.next()) |v| {
                for (v.positions, v.paths) |position, *path| {
                    //const newpos = vec4(position.x(), position.y(), 0.0, 1.0);
                    const newpos = vec2(position.x(), position.y());
                    const delta = newpos.sub(&path.vertices[0]);
                    for (path.vertices) |*vertex| {
                        vertex.* = vertex.add(&delta);
                    }
                }
            }
        }
    }

    const frame_render_pass = renderer_mod.state().frame_render_pass;

    // Shapes
    shapes.state().render_pass = frame_render_pass;
    shapes.schedule(.update_shapes); // Only send if shapes have changed
    shapes.schedule(.pre_render);
    shapes.schedule(.render);

    // Finish the frame once rendering is done.
    self.schedule(.end_frame);
}

fn endFrame(
    core: *mach.Core.Mod,
    renderer_mod: *renderer.Mod,
) !void {
    renderer_mod.schedule(.end_frame);

    // Every second, update the window title with the FPS
    try core.state().printTitle(
        core.state().main_window,
        "Collision [ {d}fps ]",
        .{
            core.state().frameRate(),
        },
    );
}

//**************************************
// Internal functions
//**************************************
fn vec2FromPosition(pos: mach.Core.Position) Vec2 {
    return vec2(@floatCast(pos.x), @floatCast(pos.y));
}
fn findObjectSelection(entities: *mach.Entities.Mod, pos: Vec2) ?mach.EntityID {
    // TODO: return options: first, last, all
    const p:Collider = .{.point = math.collision.Point{ .pos = pos }};

    var q = entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .colliders = Mod.read(.collider)
    }) catch {
        return null;
    };
    //defer q.finish();

    var a: ?mach.EntityID = null;
    while (q.next()) |v| {
        for (v.ids, v.colliders) |id, collider| {
            if (collides(&p, &collider)) {
                a = id; // return id;    need to iterate until end.
            }
        }
    }

    return a;
}
fn createRectangle(self: *Mod, canvas: *Canvas, pos: Vec2, size: Vec2) !mach.EntityID {
    const rect = try drawRect(canvas, 
        pos.x() + size.x()/2.0,
        pos.y() + size.y()/2.0, 
        size.x(), 
        size.y());
    try self.set(rect, .position, pos);
    try self.set(rect, .collider, .{
        .rectangle = .{ .pos = pos, .size = size }});
    const styles = self.state().default_styles;
    try self.set(rect, .default_style, .{
        .line_style = canvas.line_style, 
        .fill_style = canvas.fill_style
    });
    try self.set(rect, .hover_style, styles.hover_style);
    try self.set(rect, .selected_style, styles.selected_style);

    return rect;
}

fn createCircle(self: *Mod, canvas: *Canvas, pos: Vec2, radius: f32) !mach.EntityID {
    const circle = try drawCircle(canvas, 
        pos.x(),
        pos.y(), 
        2.0 * radius, 
        2.0 * radius);
    try self.set(circle, .position, pos);
    try self.set(circle, .collider, .{
        .circle = .{ .pos = pos, .radius = radius }});

    const styles = self.state().default_styles;
    try self.set(circle, .default_style, .{
        .line_style = canvas.line_style, 
        .fill_style = canvas.fill_style
    });
    try self.set(circle, .hover_style, styles.hover_style);
    try self.set(circle, .selected_style, styles.selected_style);

    return circle;
}

fn createLine(self: *Mod, canvas: *Canvas, p0: Vec2, p1: Vec2) !mach.EntityID {
    const line = try drawLine(canvas, 
        p0.x(),
        p0.y(), 
        p1.x(),
        p1.y());
    try self.set(line, .position, p0);
    try self.set(line, .collider, .{
        .line = .{ .start = p0, .end = p1, .threshold = canvas.line_style.width }});

    const styles = self.state().default_styles;
    try self.set(line, .default_style, .{
        .line_style = canvas.line_style, 
        .fill_style = canvas.fill_style
    });
    try self.set(line, .hover_style, styles.hover_style);
    try self.set(line, .selected_style, styles.selected_style);

    return line;
}

fn createTriangle(self: *Mod, canvas: *Canvas, p0: Vec2, p1: Vec2, p2: Vec2) !mach.EntityID {
    const triangle = try drawTriangle(
        canvas,
        p0.x(),
        p0.y(),
        p1.x(),
        p1.y(),
        p2.x(),
        p2.y(),
    );
    // TODO: need to release if the triangle entity is removed
    var vertices = try self.state().allocateVertices2(3);
    vertices[0] = p0;
    vertices[1] = p1;
    vertices[2] = p2;

    try self.set(triangle, .position, p0);
    try self.set(triangle, .collider, .{
        .triangle = vertices});

    const styles = self.state().default_styles;
    try self.set(triangle, .default_style, .{
        .line_style = canvas.line_style, 
        .fill_style = canvas.fill_style
    });
    try self.set(triangle, .hover_style, styles.hover_style);
    try self.set(triangle, .selected_style, styles.selected_style);

    return triangle;
}
fn createPolygon(self: *Mod, canvas: *Canvas, vertices: []Vec2) !mach.EntityID {
    const polygon = try drawPolygon(
        canvas,
        vertices
    );

    try self.set(polygon, .position, vertices[0]);
    try self.set(polygon, .collider, .{
        .polygon = vertices});

    const styles = self.state().polygon_styles;
    try self.set(polygon, .default_style, .{
        .line_style = canvas.line_style, 
        .fill_style = canvas.fill_style
    });
    try self.set(polygon, .hover_style, styles.hover_style);
    try self.set(polygon, .selected_style, styles.selected_style);

    return polygon;
}
