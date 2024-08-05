//! Demonstration of event handling in mach.
//! 

const std = @import("std");
const mach = @import("mach");
const gfx = mach.gfx;
const math = mach.math;
const vec2 = math.vec2;
const Vec2 = math.Vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Vec4 = math.Vec4;
const Mat4x4 = math.Mat4x4;
const gpu = mach.gpu;
const shp = @import("../shapes/main.zig");
const Canvas = shp.Canvas;
const LineStyle = shp.LineStyle;
const FillStyle = shp.FillStyle;
const drawCircle = shp.drawCircle;
const drawLine = shp.drawLine;
const drawRect = shp.drawRect;
const col = shp.col;
const rgb = shp.rgb;
const util = @import("../util.zig");

const Rect = struct {
    pos: Vec2,
    size: Vec2,
};

const Layout = struct {
    keyboard: Rect,
    mouse: Rect,
    events: Rect,
    window_info: Rect,
    margin: f32,
    text_vspacing: f32,
    buttons: std.AutoHashMap(mach.Core.Key, Rect),
    mouse_buttons: std.AutoHashMap(mach.Core.MouseButton, Rect),
    key_modifiers: std.AutoHashMap(mach.Core.Key, Rect),
    mouse_modifiers: std.AutoHashMap(mach.Core.Key, Rect),
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// App state
width: f32 = 960.0,         // Width of render area - will be scaled to window
height: f32 = 540.0,        // Height of render area - will be scaled to window

// Resources
allocator: std.mem.Allocator,
frame_encoder: *gpu.CommandEncoder = undefined,
frame_render_pass: *gpu.RenderPassEncoder = undefined,
shapes_canvas: mach.EntityID = undefined,
text_pipeline: mach.EntityID = undefined,
layout: Layout = undefined,
window_info_label: mach.EntityID = undefined,
focus_label: mach.EntityID = undefined,
mouse_pos_label: mach.EntityID = undefined,
mouse_pos_press_label: mach.EntityID = undefined,
mouse_pos_release_label: mach.EntityID = undefined,
input_text_label: mach.EntityID = undefined,
input_string_buffer: [30]u8 = undefined,
input_string: []u8,
pressed_keys: std.AutoHashMap(mach.Core.Key, void) = undefined,
pressed_mouse: std.AutoHashMap(mach.Core.MouseButton, void) = undefined,
key_repeat: std.AutoHashMap(mach.Core.Key, void) = undefined,
key_modifiers: std.AutoHashMap(mach.Core.Key, void) = undefined,
mouse_modifiers: std.AutoHashMap(mach.Core.Key, void) = undefined,

pub const name = .app; // The main app has to be named .app
pub const Mod = mach.Mod(@This());

pub const systems = .{
    .init = .{ .handler = init },
    .after_init = .{ .handler = afterInit },
    .deinit = .{ .handler = deinit },
    .update = .{ .handler = update },
    .input = .{ .handler = tick_input },
    .render = .{ .handler = tick_render },
    .end_frame = .{ .handler = endFrame },
};

pub const components = .{
    .velocity = .{ .type = math.Vec2, .description = ""},
};

fn init(
    self: *Mod, 
    shapes: *shp.Mod,
    entities: *mach.Entities.Mod,    
    text: *gfx.Text.Mod,
    text_pipeline: *gfx.TextPipeline.Mod,
) !void {
    const allocator = gpa.allocator();
    const shapes_canvas = try entities.new();
    try  shapes.set(shapes_canvas, .shapes_pipeline, {});
    try  shapes.set(shapes_canvas, .pipeline, shapes_canvas);

    const text_pipeline_entity = try entities.new();
    try text_pipeline.set(text_pipeline_entity, .is_pipeline, {});

    self.init(.{
        .allocator = allocator,
        .shapes_canvas = shapes_canvas,
        .text_pipeline = text_pipeline_entity,
        .pressed_keys = std.AutoHashMap(mach.Core.Key, void).init(allocator),
        .key_modifiers = std.AutoHashMap(mach.Core.Key, void).init(allocator),
        .key_repeat = std.AutoHashMap(mach.Core.Key, void).init(allocator),
        .pressed_mouse = std.AutoHashMap(mach.Core.MouseButton, void).init(allocator),
        .mouse_modifiers = std.AutoHashMap(mach.Core.Key, void).init(allocator),
        .input_string = undefined,
    });
    self.state().input_string = self.state().input_string_buffer[0..0];

    shapes.schedule(.init);
    shapes.schedule(.update);

    text.schedule(.init);
    text_pipeline.schedule(.init);

    self.schedule(.after_init);
}

fn afterInit(
    self: *Mod,
    core: *mach.Core.Mod,
    entities: *mach.Entities.Mod,
    text: *gfx.Text.Mod,
    text_style: *gfx.TextStyle.Mod,
    text_pipeline: *gfx.TextPipeline.Mod,
) !void {
    const text_pipeline_entity = self.state().text_pipeline;

    const width = core.get(core.state().main_window, .width).?;
    const height = core.get(core.state().main_window, .height).?;

    // Create a text rendering pipeline
    const style1 = try entities.new();
    try text_style.set(style1, .font_size, 36 * gfx.px_per_pt);
    try text_style.set(style1, .font_color, col(.AntiqueWhite));

    const header_style = try entities.new();
    try text_style.set(header_style, .font_size, 40 * gfx.px_per_pt);
    try text_style.set(header_style, .font_color, col(.Yellow));

    const black_style = try entities.new();
    try text_style.set(black_style, .font_size, 40 * gfx.px_per_pt);
    try text_style.set(black_style, .font_color, col(.Black));

    const layout = &self.state().layout;

    const left = -@as(f32, @floatFromInt(width))/2.0;
    const right = @as(f32, @floatFromInt(width))/2.0;
    const top = @as(f32, @floatFromInt(height))/2.0;
    const bottom = -@as(f32, @floatFromInt(height))/2.0;
    std.debug.print("left,right,top,bottom: {} {} {} {}\n", .{left,right,top,bottom});

    layout.margin = 20.0;
    layout.text_vspacing = 30;

    // Draw
    layout.keyboard = .{ 
        .pos = vec2(left + layout.margin, top - 2.0 * layout.margin),
        .size = vec2(600.0, 300.0)
    };
    layout.mouse = .{ 
        .pos = vec2(right - 250.0, top - 2.0 * layout.margin),
        .size = vec2(250.0 - 2.0 * layout.margin, 300.0)
    };

    layout.events = .{ 
        .pos = vec2(left + layout.margin, top - 3.0 * layout.margin - 300),
        .size = vec2(600.0, 120.0)
    };

    layout.window_info = .{ 
        .pos = vec2(right - 250.0, top - 3.0 * layout.margin - 300),
        .size = vec2(250.0 - 2.0 * layout.margin, 120.0)
    };

    self.state().window_info_label = try util.createText(
        entities, 
        text, 
        text_pipeline_entity, 
        black_style, 
        layout.window_info.pos.x() + layout.margin, layout.window_info.pos.y() - 0.25 * layout.margin - layout.text_vspacing, 
        "Window info", .{});


    _ = try util.createText(
        entities, 
        text, 
        text_pipeline_entity, 
        header_style, 
        layout.keyboard.pos.x() + layout.margin, layout.keyboard.pos.y() - layout.margin, 
        "Keyboard", .{});

    self.state().focus_label = try util.createText(
        entities, 
        text, 
        text_pipeline_entity, 
        black_style, 
        layout.keyboard.pos.x() + layout.margin, bottom + 2.0 * layout.margin, 
        " ", .{});

    _ = try util.createText(
        entities, 
        text, 
        text_pipeline_entity, 
        header_style, 
        layout.mouse.pos.x() + layout.margin, layout.mouse.pos.y() - layout.margin,  
        "Mouse", .{});

    _ = try util.createText(
        entities, 
        text, 
        text_pipeline_entity, 
        style1, 
        layout.mouse.pos.x() + layout.margin, layout.mouse.pos.y() - layout.text_vspacing - layout.margin, 
        "Pos: ", .{});

    _ = try util.createText(
        entities, 
        text, 
        text_pipeline_entity, 
        style1, 
        layout.mouse.pos.x() + layout.margin, layout.mouse.pos.y() - 2.0 * layout.text_vspacing - layout.margin, 
        "Press: ", .{});

    _ = try util.createText(
        entities, 
        text, 
        text_pipeline_entity, 
        style1, 
        layout.mouse.pos.x() + layout.margin, layout.mouse.pos.y() - 3.0 * layout.text_vspacing - layout.margin, 
        "Rel: ", .{});

    self.state().mouse_pos_label = try util.createText(
        entities, 
        text, 
        text_pipeline_entity, 
        style1, 
        layout.mouse.pos.x() + 100.0, layout.mouse.pos.y() - layout.text_vspacing - layout.margin, 
        "x,y", .{});

    self.state().mouse_pos_press_label = try util.createText(
        entities, 
        text, 
        text_pipeline_entity, 
        style1, 
        layout.mouse.pos.x() + 100.0, layout.mouse.pos.y() - layout.text_vspacing * 2.0 - layout.margin, 
        "x,y", .{});

    self.state().mouse_pos_release_label = try util.createText(
        entities, 
        text, 
        text_pipeline_entity, 
        style1, 
        layout.mouse.pos.x() + 100.0, layout.mouse.pos.y() - layout.text_vspacing * 3.0 - layout.margin, 
        "x,y", .{});
        
    // Draw keyboard
    {
        const key_row_1 = [_][]const u8{
            "A", "B", "C", "D", "E", "F", "G", "H", 
            "I", "J", "K", "L", "M", "N", "O", "P", 
            "Q", "R", "S", "T", "U", "V", "W", "X", 
            "Y", "Z"};
        const key_enum_row_1 = [_]mach.Core.Key{
            .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o,
            .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z
        };

        const key_row_2 = [_][]const u8{
            "Tab", "Caps", "LShift", "LCtrl", "Super", "LAlt", "Space", "RAlt", 
            "RCtrl", "Left", "Up", "Down", "Right", "RShift", "Enter", "BackS", 
            "Del"};
        const key_enum_row_2 = [_]mach.Core.Key{
            .tab, .caps_lock, .left_shift, .left_control, .left_super, .left_alt, .space, .right_alt,
            .right_control, .left, .up, .down, .right, .right_shift, .enter, .backspace,
            .delete
        };

        const step_x = 20.0;
        var start_x = layout.keyboard.pos.x() + layout.margin;
        var start_y = layout.keyboard.pos.y() - layout.margin;

        layout.buttons = std.AutoHashMap(mach.Core.Key, Rect).init(self.state().allocator);

        start_y -= layout.text_vspacing;
        for (key_row_1, key_enum_row_1) |k, e| {
            _ = try util.createText(
                entities, 
                text, 
                text_pipeline_entity, 
                style1, 
                start_x, start_y, 
                "{s}", .{k});
            try layout.buttons.put(e, .{.pos = vec2(start_x, start_y), .size = vec2(step_x, layout.text_vspacing)});
            start_x += step_x;
        }

        start_x = layout.keyboard.pos.x() + layout.margin; 
        start_y -= layout.text_vspacing;
        const max_cols = 9;
        var cols: u32 = 0;
        for (key_row_2, key_enum_row_2) |k, e| {
            _ = try util.createText(
                entities, 
                text, 
                text_pipeline_entity, 
                style1, 
                start_x, start_y, 
                "{s}", .{k});
            try layout.buttons.put(e, .{.pos = vec2(start_x, start_y), .size = vec2(2.8*step_x, layout.text_vspacing)});
            start_x += 2.8 * step_x;
            cols += 1;
            if (cols > max_cols) {
                cols = 0;
                start_x = layout.keyboard.pos.x() + layout.margin; 
                start_y -= layout.text_vspacing;
            }
        }

        start_y -= layout.text_vspacing;
        start_x = layout.keyboard.pos.x() + layout.margin; 
        _ = try util.createText(
            entities, 
            text, 
            text_pipeline_entity, 
            header_style, 
            layout.keyboard.pos.x() + layout.margin, start_y, 
            "Keyboard modifiers", .{});

        _ = try util.createText(
            entities, 
            text, 
            text_pipeline_entity, 
            header_style, 
            layout.keyboard.pos.x() + layout.margin, start_y - 2.0 * layout.text_vspacing, 
            "Mouse modifiers", .{});

        start_y -= layout.text_vspacing;
        const key_modifiers = [_][]const u8{
            "Shift", "Control", "Alt", "Super", "Caps Lock", "Num Lock"};
        const key_modifiers_enum = [_]mach.Core.Key{
            .left_shift, .left_control, .left_alt, .left_super, .caps_lock, .num_lock
        };
        layout.key_modifiers = std.AutoHashMap(mach.Core.Key, Rect).init(self.state().allocator);
        layout.mouse_modifiers = std.AutoHashMap(mach.Core.Key, Rect).init(self.state().allocator);

        for (key_modifiers, key_modifiers_enum) |modifier, e| {
            _ = try util.createText(
                entities, 
                text, 
                text_pipeline_entity, 
                style1, 
                start_x, start_y, 
                "{s}", .{modifier});
            try layout.key_modifiers.put(e, .{.pos = vec2(start_x, start_y), .size = vec2(4.5 * step_x, layout.text_vspacing)});

            _ = try util.createText(
                entities, 
                text, 
                text_pipeline_entity, 
                style1, 
                start_x, start_y - 2.0 * layout.text_vspacing, 
                "{s}", .{modifier});
            try layout.mouse_modifiers.put(e, .{.pos = vec2(start_x, start_y - 2.0 * layout.text_vspacing), .size = vec2(4.5 * step_x, layout.text_vspacing)});

            start_x += 4.5 * step_x;
        }

        start_y -= 3.0 * layout.text_vspacing;
        _ = try util.createText(
            entities, 
            text, 
            text_pipeline_entity, 
            header_style, 
            layout.keyboard.pos.x() + layout.margin, start_y, 
            "Input string: ", .{});

        self.state().input_text_label = try util.createText(
                entities, 
                text, 
                text_pipeline_entity, 
                style1, 
                layout.keyboard.pos.x() + 150.0, start_y, 
                " *** input text *** ", .{});            

    }

    // Draw mouse buttons
    {
        const button_label = [_][]const u8{
            "Left", "Mid", "Right",
            "Four", "Five", "Six", 
            "Seven", "Eight"};

        const button_enum = [_]mach.Core.MouseButton{
            .left, .middle, .right,
            .four, .five, .six,
            .seven, .eight
        };

        const button_x = [_]f32{
            0.0, 1.0, 2.0,
            0.0, 1.0, 2.0,
            0.0, 1.0,
        };

        const button_y = [_]f32{
            0.0, 0.0, 0.0,
            1.0, 1.0, 1.0,
            2.0, 2.0,
        };

        const step_x = 60.0;
        const start_x = layout.mouse.pos.x() + layout.margin;
        const start_y = layout.mouse.pos.y() - 5.0 * layout.text_vspacing - 2.0 * layout.margin;

        layout.mouse_buttons = std.AutoHashMap(mach.Core.MouseButton, Rect).init(self.state().allocator);
        for (button_label, button_enum, button_x, button_y) |l, e, x, y| {
            _ = try util.createText(
                entities, 
                text, 
                text_pipeline_entity, 
                style1, 
                start_x + x * step_x, 
                start_y - y * layout.text_vspacing, 
                "{s}", .{l});
            try layout.mouse_buttons.put(e, .{
                .pos = vec2(start_x + x * step_x, start_y - y * layout.text_vspacing), 
                .size = vec2(step_x, layout.text_vspacing)});
        }
    }    

    // _ = try util.createText(
    //     entities, 
    //     text, 
    //     text_pipeline_entity, 
    //     style1, 
    //     layout.events_pos.x, layout.events_pos.y, 
    //     "Events", .{});

    // _ = try util.createText(
    //     entities, 
    //     text, 
    //     text_pipeline_entity, 
    //     style1, 
    //     layout.window_info.x, layout.window_info.y, 
    //     "Window info", .{});

    text_pipeline.schedule(.update);
}

fn deinit(
    self: *Mod,
    shapes: *shp.Mod,
    text: *gfx.Text.Mod,
    text_pipeline: *gfx.TextPipeline.Mod,
) !void {
    shapes.schedule(.deinit);
    text_pipeline.schedule(.deinit);
    text.schedule(.deinit);
    self.state().layout.buttons.deinit();
    self.state().pressed_keys.deinit();
    self.state().layout.mouse_buttons.deinit();
    self.state().pressed_mouse.deinit();
    self.state().mouse_modifiers.deinit();
    self.state().layout.mouse_modifiers.deinit();
    self.state().layout.key_modifiers.deinit();
    self.state().key_modifiers.deinit();
    self.state().key_repeat.deinit();
}

fn update(
    core: *mach.Core.Mod,
    self: *Mod,
) !void {
    if (core.state().should_close) {
        return;
    }

    self.schedule(.input);
    self.schedule(.render);
}

fn update_modifiers(modifiers: *std.AutoHashMap(mach.Core.Key, void), mods: mach.Core.KeyMods) !void {
    modifiers.clearRetainingCapacity();
    if (mods.shift) { try modifiers.put(.left_shift, {}); }
    if (mods.control) { try modifiers.put(.left_control, {}); }
    if (mods.alt) { try modifiers.put(.left_alt, {}); }
    if (mods.super) { try modifiers.put(.left_super, {}); }
    if (mods.caps_lock) { try modifiers.put(.caps_lock, {}); }
    if (mods.num_lock) { try modifiers.put(.num_lock, {}); }
}

fn tick_input(
    self: *Mod,
    core: *mach.Core.Mod,
    text: *gfx.Text.Mod    
) !void {        
    self.state().key_repeat.clearRetainingCapacity();

    var iter = core.state().pollEvents();
    // Handle inputs
    // KeyEvent
    //      key: Key                - key enums e.g. a,b,c, ... , home, delete, ....
    //      mods: KeyMods           - shift, control, alt, super, caps_lock, num_lock
    //
    // MouseButtonEvent
    //      button: MouseButton     - left, right, middle, four, five, six, seven, eight
    //      pos: Position
    //      mods: KeyMods
    //
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                try self.state().pressed_keys.put(ev.key, {});
                // KeyEvent
                // switch (ev.key) {
                //     .escape, .q => core.schedule(.exit),
                //     else => {},
                // }
                std.debug.print("Key pressed {}\n", .{ev});
                try update_modifiers(&self.state().key_modifiers, ev.mods);

                if (ev.key == .backspace and self.state().input_string.len > 0) {
                    self.state().input_string.len -= 1;
                }

                if (ev.key == .f11) {
                    if (core.state().displayMode() != .fullscreen) {
                        core.state().setDisplayMode(.fullscreen);
                    } else {
                        core.state().setDisplayMode(.windowed);
                    }
                }
            },
            .key_repeat => |ev| {
                try self.state().key_repeat.put(ev.key, {});
                if (ev.key == .backspace and self.state().input_string.len > 0) {
                    self.state().input_string.len -= 1;
                }
            },
            .key_release => |ev| {
                _ = self.state().pressed_keys.remove(ev.key);
                try update_modifiers(&self.state().key_modifiers, ev.mods);
            },
            .char_input => |ev| {
                if (ev.codepoint != 8 and ev.codepoint < 256) { // not backspace and 8 bit
                    if (self.state().input_string.len == self.state().input_string_buffer.len) {
                        self.state().input_string.len = 0;
                    }
                    self.state().input_string.len += 1;
                    // TODO (hj): Convert from utf-8
                    self.state().input_string[self.state().input_string.len-1] = @as(u8, @truncate(ev.codepoint));
                }
                if (self.state().input_string.len > 0) {
                    try util.updateText(text, self.state().input_text_label, "{s}", .{self.state().input_string});
                } else { 
                    // TODO (hj): Crashes on empty string
                    try util.updateText(text, self.state().input_text_label, "{s}", .{" "});
                }
            },
            .mouse_press => |ev| {
                const pos = util.windowToCanvas(core, ev.pos);
                try self.state().pressed_mouse.put(ev.button, {});
                try update_modifiers(&self.state().mouse_modifiers, ev.mods);
                try util.updateText(text, self.state().mouse_pos_press_label, "{d:.0} , {d:.0}", .{pos.x(), pos.y()});
                std.debug.print("Mouse pressed {}\n", .{ev});

            },
            .mouse_release => |ev| {
                const pos = util.windowToCanvas(core, ev.pos);
                _ = self.state().pressed_mouse.remove(ev.button);
                try update_modifiers(&self.state().mouse_modifiers, ev.mods);
                try util.updateText(text, self.state().mouse_pos_release_label, "{d:.0} , {d:.0}", .{pos.x(), pos.y()});
            },
            .mouse_motion => |ev| {
                const pos = util.windowToCanvas(core, ev.pos);
                // TOOD (hj) : option to display both raw mouse coords and mouse in app/canvas coords

                try util.updateText(text, self.state().mouse_pos_label, "{d:.0} , {d:.0}", .{pos.x(), pos.y()});

            },
            .mouse_scroll => |ev| {
                //_ = ev;
                std.debug.print("Mouse scroll {}\n", .{ev});
            },
            .framebuffer_resize => |ev| {
                std.debug.print("Framebuffer resize {}", .{ev});
            },
            .focus_gained => |_| {
                self.state().key_modifiers.clearRetainingCapacity();
                self.state().mouse_modifiers.clearRetainingCapacity();
                self.state().pressed_keys.clearRetainingCapacity();

                try util.updateText(text, self.state().focus_label, "Has focus", .{});
            },
            .focus_lost => |_| {
                self.state().key_modifiers.clearRetainingCapacity();
                self.state().mouse_modifiers.clearRetainingCapacity();
                self.state().pressed_keys.clearRetainingCapacity();

                try util.updateText(text, self.state().focus_label, "Lost focus", .{});
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
    shapes: *shp.Mod,
    text_pipeline: *gfx.TextPipeline.Mod,
    text: *gfx.Text.Mod    
) !void {
    const width: f32 = @floatFromInt(core.get(core.state().main_window, .width).?);
    const height: f32 = @floatFromInt(core.get(core.state().main_window, .height).?);

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
    shapes.state().render_pass = self.state().frame_render_pass;

    // Clear all shapes
    // TODO: create a remove helper
    {
        var q = try entities.query(.{
            .ids = mach.Entities.Mod.read(.id),
            .pipelines = shp.Mod.read(.pipeline),
        });
        while (q.next()) |e| {
            for (e.ids, e.pipelines) |id, pipeline| {
                // TODO (hj) the pipelines have a pipeline component also and are being deleted. Need a shape marker.
                // TODO (hj) ECS query needs filter by value.
                if (pipeline == shapes_canvas and id > 2) {
                    try entities.remove(id);
                }
            }
        }
    }

    // Draw shapes
    var canvas = Canvas{
        .entities = entities, 
        .shapes = shapes, 
        .canvas = shapes_canvas,
        .line_style = .{.color =  col(.Ivory), .width = 4.0},
        .fill_style = .{.color =  col(.DarkBlue)},
    };

    canvas.fill_style = .{.color = col(.LightGrey)};
    canvas.line_style = .{.color = col(.DarkGrey), .width = 2.0};

    _ = try drawRect(&canvas, 
        0.0, 0.0, width-20.0, height-20.0);

    canvas.line_style = .{.color = col(.Ivory), .width = 4.0};
    canvas.fill_style = .{.color = col(.DarkBlue)};

    const layout = self.state().layout;
    _ = try drawRect(&canvas, 
        layout.keyboard.pos.x() + layout.keyboard.size.x()/2.0, layout.keyboard.pos.y() - layout.keyboard.size.y() / 2.0, 
        layout.keyboard.size.x(), layout.keyboard.size.y());

    _ = try drawRect(&canvas, 
        layout.mouse.pos.x() + layout.mouse.size.x() / 2.0, layout.mouse.pos.y() - layout.mouse.size.y() / 2.0, 
        layout.mouse.size.x(), layout.mouse.size.y());

    canvas.fill_style = .{.color = col(.LightBlue)};
    canvas.line_style = .{.color = col(.Ivory), .width = 6.0};

    _ = try drawRect(&canvas, 
        layout.events.pos.x() + layout.events.size.x() / 2.0, layout.events.pos.y() - layout.events.size.y() / 2.0, 
        layout.events.size.x(), layout.events.size.y());

    _ = try drawRect(&canvas, 
        layout.window_info.pos.x() + layout.window_info.size.x() / 2.0, layout.window_info.pos.y() - layout.window_info.size.y() / 2.0, 
        layout.window_info.size.x(), layout.window_info.size.y());

    canvas.fill_style = .{.color = col(.DarkGreen)};
    canvas.line_style = .{.color =  col(.Ivory), .width = 4.0};

    {
        var iter = self.state().pressed_keys.keyIterator();
        while (iter.next()) |key| {
            if (self.state().layout.buttons.get(key.*)) |k| {
                _ = try drawRect(&canvas, 
                    k.pos.x() + k.size.x() / 2.0 - 5.0, 
                    k.pos.y() - k.size.y() / 2.0 + layout.text_vspacing / 1.5, 
                    k.size.x() - 5.0, 
                    k.size.y());
            }
        }
    }

    {
        var iter = self.state().pressed_mouse.keyIterator();
        while (iter.next()) |key| {
            if (self.state().layout.mouse_buttons.get(key.*)) |k| {
                _ = try drawRect(&canvas, 
                    k.pos.x() + k.size.x() / 2.0 - 5.0, 
                    k.pos.y() - k.size.y() / 2.0 + layout.text_vspacing / 1.5, 
                    k.size.x() - 5.0, 
                    k.size.y());
            }
        }
    }

    {
        var iter = self.state().key_modifiers.keyIterator();
        while (iter.next()) |key| {
            if (self.state().layout.key_modifiers.get(key.*)) |k| {
                _ = try drawRect(&canvas, 
                    k.pos.x() + k.size.x() / 2.0 - 5.0, 
                    k.pos.y() - k.size.y() / 2.0 + layout.text_vspacing / 1.5, 
                    k.size.x() - 5.0, 
                    k.size.y());
            }
        }
    }

    {
        var iter = self.state().mouse_modifiers.keyIterator();
        while (iter.next()) |key| {
            if (!core.state().keyPressed(key.*)) {
                //@panic("Mismatched key state\n");

            }

            if (self.state().layout.mouse_modifiers.get(key.*)) |k| {
                _ = try drawRect(&canvas, 
                    k.pos.x() + k.size.x() / 2.0 - 5.0, 
                    k.pos.y() - k.size.y() / 2.0 + layout.text_vspacing / 1.5, 
                    k.size.x() - 5.0, 
                    k.size.y());
            }
        }
    }

    canvas.fill_style = .{.color = col(.DarkRed)};
    {
        var iter = self.state().key_repeat.keyIterator();
        while (iter.next()) |key| {
            if (self.state().layout.buttons.get(key.*)) |k| {
                _ = try drawRect(&canvas, 
                    k.pos.x() + k.size.x() / 2.0 - 5.0, 
                    k.pos.y() - k.size.y() / 2.0 + layout.text_vspacing / 1.5, 
                    k.size.x() - 5.0, 
                    k.size.y());
            }
        }
    }

    // framebuffer format, width, height
    // fullscreen
    try util.updateText(text, self.state().window_info_label, "Size: \n {d:.0} {d:.0}", .{width, height});

    // Add a test for these functions
    //core.state().keyPressed(key.*)
    //core.state().keyReleased(key.*)
    //core.state().mousePressed(key.*)
    //core.state().mouseReleased(key.*)
    //core.state().mousePosition(key.*)

    shapes.schedule(.update_shapes);        // Only happens is shapes have changed
    shapes.schedule(.pre_render);           
    shapes.schedule(.render);

    // Render text
    text.schedule(.update);
    text_pipeline.state().render_pass = self.state().frame_render_pass;
    text_pipeline.schedule(.pre_render);
    text_pipeline.schedule(.render);

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
        "events_app [ {d}fps ] [ Input {d}hz ]",
        .{
            // TODO(Core)
            core.state().frameRate(),
            core.state().inputRate(),
        },
    );
}
