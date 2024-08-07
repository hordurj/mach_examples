//! Extra functions to suplement mach.math.collision
//! 

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

pub const ColliderType = enum {
    rectangle,
    circle,
    point,
    triangle,
    polygon,
    line
};
pub const Collider = union(ColliderType) {
    rectangle: collision.Rectangle,
    circle: collision.Circle,
    point: collision.Point,
    triangle: []Vec2,
    polygon: []Vec2,
    line: collision.Line
};

/// Minimum distance of vn-v0 on n
pub fn minProjectionDistance(n: Vec2, v0: Vec2, v: []const Vec2) f32 {
    var min_d = n.dot(&v[0].sub(&v0));
    for (v[1..]) |vb| {
        min_d = @min(min_d, n.dot(&vb.sub(&v0)));
    }
    return min_d;
}

pub fn minmaxProjectionDistance(n: Vec2, v0: Vec2, v: []const Vec2) Vec2 {
    var max_d = n.dot(&v[0].sub(&v0));
    var min_d = n.dot(&v[0].sub(&v0));
    for (v[1..]) |vb| {
        const d = n.dot(&vb.sub(&v0));
        if (d < min_d) {
            min_d = d;
        } else if (d > max_d) {
            max_d = d;
        }
    }
    return vec2(min_d, max_d);
}

pub fn distanceToLineSegment(p: Vec2, a: Vec2, b: Vec2) f32 {
    const pa = p.sub(&a);
    const ab = b.sub(&a);
    const l = ab.dot(&pa) / ab.len2();
    const p_on_ab = ab.mulScalar(math.clamp(l, 0.0, 1.0)); 
    return pa.sub(&p_on_ab).len();
}

/// Use SAT to determine if the two shapes intersect.
/// if the number of vertices is greater than 2 it is assumed
/// the shape is closed, otherwise with
pub fn collideSat(va: []const Vec2, vb: []const Vec2, min_distance: f32) bool {
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

pub fn verticesFromRect(rect: *const collision.Rectangle) [4]Vec2 {
    // Pos is bottom left
    return [_]Vec2{
                rect.pos,
                rect.pos.add(&vec2(rect.size.x(), 0.0)),
                rect.pos.add(&vec2(rect.size.x(), rect.size.y())),
                rect.pos.add(&vec2(0.0, rect.size.y())),
    };
}

pub fn collideLine(line_a: *const collision.Line, collider_b: *const Collider) bool {
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

pub fn collidePolygon(polygon_a: []Vec2, collider_b: *const Collider) bool {
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

pub fn collides(collider_a: *const Collider, collider_b: *const Collider) bool {
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
