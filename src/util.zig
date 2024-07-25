//! Utility functions for the examples
const mach = @import("mach");
const math = mach.math;
const gfx = mach.gfx;
const Vec2 = math.Vec2;
const vec2 = math.vec2;
const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Mat4x4 = math.Mat4x4;

pub fn window_to_canvas(core: *mach.Core.Mod, pos: mach.Core.Position) Vec2 {
    const window = core.state().main_window;
    const width:f32 = @floatFromInt(core.get(window, .width).?);
    const height:f32 = @floatFromInt(core.get(window, .height).?);
    var x: f32 = @floatCast(pos.x); x -= width / 2.0;
    var y: f32 = @floatCast(pos.y); y = -y + height / 2.0;
    return vec2(x, y);
}

pub fn createText(entities: *mach.Entities.Mod, 
    text: *gfx.Text.Mod,
    pipeline_entity: mach.EntityID, 
    style: mach.EntityID, 
    x: f32,
    y: f32,
    comptime fmt: []const u8, 
    args: anytype
) !mach.EntityID {
    // Create some text
    const text_entity = try entities.new();
    try text.set(text_entity, .pipeline, pipeline_entity);
    try text.set(text_entity, .transform, Mat4x4.translate(vec3(x, y, 0)));
    try gfx.Text.allocPrintText( text, text_entity, style, fmt, args);

    return text_entity;
}

pub fn updateText(text: *gfx.Text.Mod,    
    text_entity: mach.EntityID,
    comptime fmt: []const u8, 
    args: anytype
) !void {
    const styles = text.get(text_entity, .style).?;
    try gfx.Text.allocPrintText(text, text_entity, styles[0], fmt, args);
}
