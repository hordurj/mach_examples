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
const col = shp.col;
const rgb = shp.rgb;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

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

pub const name = .app; // The main app has to be named .app
pub const Mod = mach.Mod(@This());

pub const systems = .{
    .init = .{ .handler = init },
    .deinit = .{ .handler = deinit },
    .after_init = .{ .handler = afterInit },
    .update = .{ .handler = update },
    .input = .{ .handler = tick_input },
    .render = .{ .handler = tick_render },
    .end_frame = .{ .handler = endFrame },
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

pub const components = .{
    .position = .{ .type = Vec2 },
    .collider = .{ .type = Collider },
    .selected_style = .{ .type = Style },
    .hover_style = .{ .type = Style },
    .default_style = .{ .type = Style },
    .marker = .{ .type = void },
};

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
    std.debug.print("Draw triangle {}\n", .{canvas.fill_style.color});
    // TODO: need to release if the triangle entity is removed
    var vertices = try self.state().allocator.alloc(Vec2, 3);
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

fn createPolygon(self: *Mod, canvas: *Canvas, points: []Vec2) !mach.EntityID {
    _ = self;
    _ = canvas;
    _ = points;

    // Create
}

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
    shapes: *shp.Mod,
) !void {
    shapes.schedule(.deinit);
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

    self.init(.{
        .allocator = allocator,
        .shapes_canvas = shapes_canvas,
        .triangle_canvas = triangle_canvas,
        .default_styles = default_styles,
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

fn vec2FromPosition(pos: mach.Core.Position) Vec2 {
    return vec2(@floatCast(pos.x), @floatCast(pos.y));
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
                else => return false
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
                else => return false
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
                .point => |_| {
                    return false;           // Point with a thinkness ?? That is a circle.
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
        else => {
            return false;
        }
    }
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

fn tick_input(self: *Mod, core: *mach.Core.Mod, entities: *mach.Entities.Mod, shapes: *shp.Mod) !void {
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
                        const mouse_pos = core.state().mousePosition();
                        const pos = util.window_to_canvas(core, mouse_pos);
                        _ = try createCircle(self, &canvas, pos, 50.0);
                    },
                    .r => {
                        // Create circle at mouse location.
                        const mouse_pos = core.state().mousePosition();
                        const pos = util.window_to_canvas(core, mouse_pos);
                        _ = try createRectangle(self, &canvas, pos, vec2(150.0, 100.0));
                    },
                    .l => {
                        // draw line
                        _ = try createLine(self, &canvas, vec2(-400.0, -200.0), vec2(-200.0, -50.0));
                    },
                    .t => {
                        // draw triangle
                        
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

                    },
                    .p => {
                        // draw polygon
                    },
                    else => {},
                }
            },
            .mouse_press => |ev| {
                // Check if any object is selected
                const pos = util.window_to_canvas(core, ev.pos);
                const selected_object = findObjectSelection(entities, pos);
                if (selected_object) |obj_id| {
                    self.state().selected_object = selected_object;
                    if (self.get(obj_id, .position)) |position| {
                        self.state().selected_pick_point = pos.sub(&position);
                    }
                    // if (shapes.get(obj_id, .circle)) |circle| {
                    //     self.state().selected_pick_point = pos.sub(&circle.center);
                    //     try shapes.set(obj_id, .line_style, self.state().default_styles.selected_style.line_style);
                    //     try shapes.set(obj_id, .fill_style, self.state().default_styles.selected_style.fill_style);
                    // }
                }
            },
            .mouse_release => |_| {
                // if (self.state().selected_object) |obj_id| {
                //     try shapes.set(obj_id, .line_style, self.state().default_styles.default_style.line_style);
                //     try shapes.set(obj_id, .fill_style, self.state().default_styles.default_style.fill_style);
                // }
                self.state().selected_object = null;
                // Release active object and restore
            },
            .mouse_motion => |ev| {
                // if left mouse button down or in drag mode and an object selected, move object
                const pos = util.window_to_canvas(core, ev.pos);
                if (self.state().selected_object) |obj_id| {
                    try self.set(obj_id, .position, pos.sub(&self.state().selected_pick_point));
                }
                //const selected_object = findObjectSelection(entities, pos);
                //if (selected_object) |obj_id| {
                //    std.debug.print("Inside {} \n", .{obj_id});
                //}
            },
            .close => core.schedule(.exit),
            else => {},
        }
    }
}

fn tick_render(
    self: *Mod,
    core: *mach.Core.Mod,
    entities: *mach.Entities.Mod,
    shapes: *shp.Mod,
    renderer_mod: *renderer.Mod,
) !void {
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
    const pos = util.window_to_canvas(core, mouse_pos);
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
                    fill_style.* = .{ .color = col(.Green)};
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
