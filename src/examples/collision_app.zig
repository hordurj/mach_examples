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

const ColliderType = enum {
    rectangle,
    circle,
    point,
    triangle,
    polygon,
    line
};
const Collider = union(ColliderType) {
    rectangle: collision.Rectangle,
    circle: collision.Circle,
    point: collision.Point,
    triangle: []Vec2,
    polygon: []Vec2,
    line: collision.Line
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

    // Clear all marker entitites
    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .markers = Mod.read(.marker),
    });
    while (q.next()) |v| {
        for (v.ids) |id| {
            try entities.remove(id);
        }
    }

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
fn render(
    self: *Mod,
    core: *mach.Core.Mod,
    entities: *mach.Entities.Mod,
    shapes: *shp.Mod,
    renderer_mod: *renderer.Mod,
) !void {
    self.state().scene_update_required = true; // Always update for now.

    if (self.state().scene_update_required) {
        self.state().scene_update_required = false;

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
                .positions = Mod.read(.position),
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
                        |obj_id, position, *collider, *line_style, *fill_style, 
                        default_style, hover_style, selected_style| 
                {
                    switch (collider.*) {
                        .circle => |*circle_collider| { circle_collider.pos = position; },
                        .rectangle => |*rectangle_collider| { rectangle_collider.pos = position; },
                        .line => |*line_collider| { 
                            const delta = line_collider.end.sub(&line_collider.start);
                            line_collider.start = position; 
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

                    // TODO: only need to change styles if mode is changing (selected, hover, default, ...)
                    if (obj_id == self.state().selected_object) {
                        line_style.* = selected_style.line_style;
                        fill_style.* = selected_style.fill_style;
                        continue ;
                    }
                    if (collides(&point, collider)) {
                        line_style.* = hover_style.line_style;
                        fill_style.* = hover_style.fill_style;
                    } else {
                        line_style.* = default_style.line_style;
                        fill_style.* = default_style.fill_style;
                    }

                    // Check if object collides with another collider
                    var q2 = try entities.query(.{
                        .ids = mach.Entities.Mod.read(.id),
                        .colliders = Mod.read(.collider),
                    });
                    var collision_detected = false;
                    while (q2.next()) |v2| {
                        for (v2.ids, v2.colliders) |id_b, collider_b| {
                            if (obj_id != id_b and collides(collider, &collider_b)) {
                                collision_detected = true;

                                switch (collider.*) {
                                    .rectangle => |rect_a| {
                                        switch (collider_b) {
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
                        fill_style.*.color = col(.Green);
                        line_style.*.color = col(.Purple);
                    }
                }
            }
        }

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

/// Minimum distance of vn-v0 on n
fn minProjectionDistance(n: Vec2, v0: Vec2, v: []const Vec2) f32 {
    var min_d = n.dot(&v[0].sub(&v0));
    for (v[1..]) |vb| {
        min_d = @min(min_d, n.dot(&vb.sub(&v0)));
    }
    return min_d;
}

fn distanceToLineSegment(p: Vec2, a: Vec2, b: Vec2) f32 {
    const pa = p.sub(&a);
    const ab = b.sub(&a);
    const l = ab.dot(&pa) / ab.len2();
    const p_on_ab = ab.mulScalar(math.clamp(l, 0.0, 1.0)); 
    return pa.sub(&p_on_ab).len();
}

/// Use SAT to determine if the two shapes intersect.
/// if the number of vertices is greater than 2 it is assumed
/// the shape is closed, otherwise with
fn collideSat(va: []const Vec2, vb: []const Vec2, min_distance: f32) bool {
    //std.debug.print("Collidesat\n", .{});

    if (va.len < 2 or vb.len < 2) { return false; }  // Or panic?

    var v0 = va[va.len-1];
    for (va[0..]) |v1| {
        const n = v1.sub(&v0).normalize(0.0); 
        const d = minProjectionDistance(vec2(n.y(), -n.x()), v0, vb);
        if (d > min_distance) { return false; }
        v0 = v1;
    }

    v0 = vb[vb.len-1];
    for (vb[0..]) |v1| {
        const n = v1.sub(&v0).normalize(0.0);
        const d = minProjectionDistance(vec2(n.y(), -n.x()), v0, va);
        if (d > min_distance) { return false; }
        v0 = v1;
    }
    return true;
}
fn verticesFromRect(rect: *const collision.Rectangle) [4]Vec2 {
    // Pos is bottom left
    return [_]Vec2{
                rect.pos,
                rect.pos.add(&vec2(rect.size.x(), 0.0)),
                rect.pos.add(&vec2(rect.size.x(), rect.size.y())),
                rect.pos.add(&vec2(0.0, rect.size.y())),
    };
}

fn collideLine(line_a: *const collision.Line, collider_b: *const Collider) bool {
    const va = [_]Vec2{line_a.start, line_a.end};

    switch (collider_b.*) {
        .circle => |circle_b| {
            const d = distanceToLineSegment(circle_b.pos, line_a.start, line_a.end);
            return (d <= circle_b.radius + line_a.threshold);
        },
        .rectangle => |rect_b| {
            const vb = verticesFromRect(&rect_b);
            return collideSat(&va, &vb, line_a.threshold);
        },
        .point => |point_b| {
            _ = point_b;
        },
        .line => |line_b| {
            const vb = [_]Vec2{line_b.start, line_b.end};
            return collideSat(&va, &vb, line_b.threshold);
        },
        .triangle => |triangle_b| {
            return collideSat(&va, triangle_b, 0.0);
        },
        .polygon=> |polygon_b| {
            return collideSat(&va, polygon_b, 0.0);
        },
    }
    return false;
}

fn collidePolygon(polygon_a: []Vec2, collider_b: *const Collider) bool {
    const va = polygon_a;

    switch (collider_b.*) {
        .circle => |circle_b| {
            const p = collision.Point{.pos = circle_b.pos};
            if (p.collidesPoly(polygon_a)) {
                return true;
            }
            var min_distance = std.math.floatMax(f32);
            var v0 = va[va.len-1];
            for (va[0..]) |v1| {
                min_distance = @min(min_distance, distanceToLineSegment(circle_b.pos, v0, v1));
                v0 = v1;
            }
            return min_distance <= circle_b.radius;

        },
        .rectangle => |rect_b| {
            const vb = verticesFromRect(&rect_b);
            return collideSat(va, &vb, 0.0);
        },
        .point => |point_b| {
            return point_b.collidesPoly(polygon_a);
        },
        .line => |line_b| {
            const vb = [_]Vec2{line_b.start, line_b.end};
            return collideSat(va, &vb, line_b.threshold);
        },
        .triangle => |triangle_b| {
            return collideSat(va, triangle_b, 0.0);
        },
        .polygon=> |polygon_b| {
            return collideSat(va, polygon_b, 0.0);
        },
    }
    return false;
}

fn collides(collider_a: *const Collider, collider_b: *const Collider) bool {
    switch (collider_a.*) {
        .rectangle => |rect_a| {
            switch (collider_b.*) {
                .rectangle => |rect_b| {
                    return rect_b.collidesRect(rect_a);
                },                
                .circle => |circle_b| {
                    return circle_b.collidesRect(rect_a);
                },
                .point => |point_b| {
                    return point_b.collidesRect(rect_a);
                },
                .line => |line_b| {
                    return collideLine(&line_b, collider_a);
                },
                .triangle, .polygon => |poly_b| {
                    return collidePolygon(poly_b, collider_a);
                }
            }
        }
        ,
        .circle => |circle_a| {
            switch (collider_b.*) {
                .rectangle => |rect_b| {
                    return circle_a.collidesRect(rect_b);
                },
                .circle => |circle_b| {
                    return circle_a.collidesCircle(circle_b);
                },
                .point => |point_b| {
                    return point_b.collidesCircle(circle_a);
                },
                .line => |line_b| {
                    return collideLine(&line_b, collider_a);
                },
                .triangle, .polygon => |poly_b| {
                    return collidePolygon(poly_b, collider_a);
                }
            }
        },
        .point => |point_a| {
            switch (collider_b.*) {
                .rectangle => |rect_b| {
                    return point_a.collidesRect(rect_b);
                },
                .circle => |circle_b| {
                    return point_a.collidesCircle(circle_b);
                },
                .point => |point_b| {
                    return point_a.pos.x() == point_b.pos.x() and point_a.pos.y() == point_b.pos.y();
                },
                .line => |line_b| {
                    return point_a.collidesLine(line_b);
                },
                .triangle => |triangle_b| {
                    return point_a.collidesTriangle(triangle_b);
                },
                .polygon => |poly_b| {
                    return point_a.collidesPoly(poly_b);
                }
            }
        },
        .line => |line_a| {
            return collideLine(&line_a, collider_b);
        },
        .triangle, .polygon => |polygon_a| {
            return collidePolygon(polygon_a, collider_b);
        }
    }
    return false;
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
