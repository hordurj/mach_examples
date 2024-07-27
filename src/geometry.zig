//! Geometry objects and functions
const std = @import("std");
const assert = std.debug.assert;
const math = @import("mach").math;
const Vec2 = math.Vec2;
const vec2 = math.vec2;

pub const Polygon = struct {
    vertices: std.ArrayList(Vec2),
    indices: std.ArrayList(u32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Polygon {
        return Polygon {
            .vertices = std.ArrayList(Vec2).init(allocator),
            .indices = std.ArrayList(u32).init(allocator),
            .allocator = allocator, 
        };
    }
    pub fn deinit(self: *Polygon) void {
        self.vertices.deinit();
        self.indices.deinit();
    } 

    pub fn add(self: *Polygon, p: Vec2) !void {
        //std.debug.print("Add vertex: {} {}\n", .{p, self.vertices.items.len});
        try self.indices.append(@truncate(self.vertices.items.len));
        try self.vertices.append(p);
    }
    
    pub fn clear(self: *Polygon) void {
        self.indices.clearRetainingCapacity();
        self.vertices.clearRetainingCapacity();
    }

    // transform
    // area
    // from_points

    /// Insert polygon at given index by creating a bridge between.
    pub fn insertPolygon(self: *Polygon, idx: u32, polygon: *Polygon) !void {
        const N: u32 = @truncate(self.vertices.items.len);
        try self.vertices.appendSlice(polygon.vertices.items);

        // Create bridge
        const M: u32 = @truncate(polygon.indices.items.len);
        _ = try self.indices.addManyAt(idx+1, M + 2);
        for (0..M) |i| {
            self.indices.items[idx+1+i] = polygon.indices.items[i] + N;
        }
        self.indices.items[idx+1+M] = polygon.indices.items[0] + N;
        self.indices.items[idx+2+M] = self.indices.items[idx];
    }

    /// Return the right most vertex as a tuple (idx, vertex)
    ///
    /// Returns (idx, vertex) st. self.vertices[idx] == vertex
    pub fn rightmostVertex(self: *const Polygon) struct {idx: u32, vertex: Vec2} {
        //return max(enumerate(self.vertices), key=lambda x: x[1].x);
        var max_idx: u32 = 0;
        var max_x = self.vertices.items[0];
        for (1.., self.vertices.items[1..]) |idx, v| {
            if (v.x() > max_x.x()) {
                max_x = v;
                max_idx = @truncate(idx);
            }
        }

        return .{.idx = max_idx, .vertex = max_x};        
    }

    /// Return true if vertex[indices[i]] is reflexive assuming CCW orientation."""
    pub fn isReflexive(self: *Polygon, i: u32) bool {
        //# TODO: Should this be determined relative to the polygon orientation?
        const N = self.indices.items.len;

        const ib = self.indices.items[(i+N-1)%N];
        const ia = self.indices.items[i];
        const ic = self.indices.items[(i+1)%N];

        const pb = self.vertices.items[ib];
        const pa = self.vertices.items[ia];
        const pc = self.vertices.items[ic];
                
        const ab = pb.sub(&pa);
        const ac = pc.sub(&pa);

        if (cross2d(ab, ac) > 0) {
            return true;
        }
        return false;
    }

    /// Merge a polygon representing a hole in this polygon.
    /// 
    /// The polygons are merged by finding a "bridge" between them.
    ///
    /// polygon is simple (no self intersecting edges)
    /// polygon should not interesect.
    pub fn merge(self: *Polygon, polygon: *Polygon) !void {
        // Find the right most vertex in the inner polygon.
        const max_x = polygon.rightmostVertex();

        var min_i: ?u32 = null;
        var v: ?Vec2 = null;
        var min_t: ?f32 = null;

        const N = self.indices.items.len;

        for (0..N) |i| {
            // Find the closest edge that a horizontal line from max_x intersects.

            const idx0 = self.indices.items[i];
            const idx1 = self.indices.items[(i+1) % N];
            const v0 = self.vertices.items[idx0];
            const v1 = self.vertices.items[idx1]; 

            // Only need to check edges going up
            if (v0.y() <= max_x.vertex.y() and max_x.vertex.y() <= v1.y()) {
                const dx = v1.x() - v0.x();
                const dy = v1.y() - v0.y();
                var t: f32 = undefined; // TODO: use block init
                if (dy != 0.0) {
                    t = dx/dy * (max_x.vertex.y() - v0.y()) - (max_x.vertex.x() - v0.x());
                } else {
                    // Horizontal edge, select the closer edge as the intersection point..
                    t = @min(v0.x()-max_x.vertex.x(), v1.x()-max_x.vertex.x());
                }
                // Check if intersected closer than previous
//                if (t > 0.0 and (min_t == null or t < min_t.?)) {
                if (t > 0.0 and (min_t == null or t < min_t.?)) {
                    min_t = t;
                    if (dy == 0.0) {
                        // # Horizontal edge, select the closer edge
                        if (v1.x() < v0.x()) {
                            v = v1;
                            min_i = @truncate((i+1) % N);
                        } else {
                            v = v0;
                            min_i = @truncate(i);
                        }
                    } else {
                        //# Select the edge further to the right
                        if (v1.x() > v0.x()) {
                            v = v1;
                            min_i = @truncate((i+1) % N);
                        } else {
                            v = v0;
                            min_i = @truncate(i);
                        }
                    }
                }
            }
        }
        
        if (min_i == null) {
            // RaiseError("Did NOT find a vertex for a bridge. Connect to first")            
            std.debug.print("Did NOT find a vertex for a bridge. Connect to first", .{});
            min_i = 0;
        } else {
            // Construct a triangle (max_x, max_x + t, v) in CCW order
            var triangle: [3]Vec2 = undefined;
            if (v.?.y() <= max_x.vertex.y()) {
                triangle = .{max_x.vertex.add(&vec2(min_t.?, 0.0)), max_x.vertex, v.?};
            } else {
                triangle = .{max_x.vertex, max_x.vertex.add(&vec2(min_t.?, 0.0)), v.?};
            }

            // Check if any reflexive vertice is inside triangle
            //   if a vertex is inside, it blocks the bridge to v.
            //   so choose the vertex with the smallest angle relative to horizontal.
            var min_abs_angle: ?f32 = null;
            var min_idx: ?u32 = null;
            for (0..self.indices.items.len) |i| {                
                if (self.indices.items[i] == max_x.idx or self.indices.items[i] == self.indices.items[min_i.?]) {
                    // skip self intersection
                    continue;
                }

                if (i != min_i.? and self.isReflexive(@truncate(i))) {
                    const p = self.vertices.items[self.indices.items[i]];
                    const hittest = hitTestTriangle(triangle, p);
                    const abs_angle = 1.0 - (p.sub(&max_x.vertex)).normalize(0.0000001).x(); // * vec2(1.0, 0.0);
                    // print("Hit test: ", hittest, triangle, p, " abs_angle: ", abs_angle, min_abs_angle, " min_idx: ", min_idx, " min_i: ", min_i, " i: ", i)
                    if (hittest and (min_abs_angle == null or abs_angle < min_abs_angle.?)) {
                        min_abs_angle = abs_angle;
                        min_idx = @truncate(i);
                    }
                } 
            }
            if (min_idx) |idx| {
                min_i = idx;
                // No vert
            }
        }
        // min_i contains an index to self.indices for the vertex that the bridge should start from.
        // Rotate
        var new_polygon = Polygon.init(self.allocator);
        defer new_polygon.deinit();

        var new_indices = std.ArrayList(u32).init(self.allocator);
        try new_indices.appendSlice(polygon.indices.items[max_x.idx..]);
        try new_indices.appendSlice(polygon.indices.items[0..max_x.idx]);
        try new_polygon.vertices.appendSlice(polygon.vertices.items);
        new_polygon.indices = new_indices;

        try self.insertPolygon(min_i.?, &new_polygon);
    }
};

pub const Triangle = [3]u32;

fn isConvex(polygon: *Polygon) bool {
    const vertices = polygon.vertices;
    const indices = polygon.indices;
    const N = indices.items.len;

    assert(N>2);

    if (N == 3) {
        return true;    
    }

    for (0..N) |i| {
        const i_0 = indices.items[(i+N-1)%N];
        const i_1 = indices.items[(i)%N];
        const i_2 = indices.items[(i+1)%N];

        const pb = vertices.items[i_0];
        const pa = vertices.items[i_1];
        const pc = vertices.items[i_2];
        
        const ab = pb.sub(&pa);
        const ac = pc.sub(&pa);

        if (cross2d(ab, ac) > 0) {
            return false;
        }
    }
    return true;
}

pub fn triangulate(polygon: *Polygon, triangles: *std.ArrayList(Triangle)) !bool {
    const vertices = polygon.vertices;
    const indices = polygon.indices;
    const N = indices.items.len;

    const convex = isConvex(polygon);
    if (convex) {
        const a = polygon.indices.items[0];
        for (0..N-2) |i| {
            const b = polygon.indices.items[i+1];
            const c = polygon.indices.items[i+2];
            try triangles.append(.{a, b, c});
        }
    } else {
        var P = try indices.clone();
        defer P.deinit();

        while (P.items.len != 0) 
        {
            const M = P.items.len;

            if (M == 3) {
                try triangles.append(.{P.items[0], P.items[1], P.items[2]});
                break;                
            }

            for (0..M) |i| {
                const ib = P.items[(i+M-1)%M];
                const ia = P.items[i];
                const ic = P.items[(i+1)%M];

                const pb = vertices.items[ib];
                const pa = vertices.items[ia];
                const pc = vertices.items[ic];
                
                const ab = pb.sub(&pa);
                const ac = pc.sub(&pa);

                if (cross2d(ab, ac) <= 0)
                {
                    var is_ear = true;

                    // Check if any points lie inside proposed ear 
                    for (0..M-3) |j| {
                        const idx = P.items[(i+j+2) % M];
                        if (idx == ia or idx == ib or idx == ic) { // in [ia, ib, ic]: # Ignore overlap from bridges
                            continue;
                        }
                        if (hitTestTriangle(.{pb, pa, pc}, vertices.items[idx])) {
                            is_ear = false;
                            break;
                        }
                    }  
                    if (is_ear) {
                        _ = P.orderedRemove(i);
                        try triangles.append(.{ib, ia, ic});
                        break;
                    }
                }
            }
            if (M == P.items.len) {
                return false;
            }
        }
    }
    return true;
}

pub fn cross2d(v1: Vec2, v2: Vec2) f32 {
    return v1.x() * v2.y() - v1.y() * v2.x();
}

pub fn hitTestTriangle(triangle: [3]Vec2, p: Vec2) bool {
    for (0..3) |i| {
        const p0 = p.sub(&triangle[i]);
        const v = triangle[(i+1)%3].sub(&triangle[i]);
        if (cross2d(p0, v) > 0) {
            return false;
        }
    }
    return true;
}

// TOOD: return a pointer or index to the point?
pub fn hitTestPoints(points: []Vec2, pos: Vec2, width: f32) ?Vec2 {
    for (points) |p| {
        if ((p.x()-width/2.0 <= pos.x() and pos.x() <= p.x()+width/2.0) and (p.y()-width/2.0 <= pos.y() and pos.y() <= p.y()+width/2.0)) {
            return p;
        }
    }
    return null;
}
