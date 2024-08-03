//! Basic renderer
//! 
//! Sets up a command encoder and render pass for other modules to use.
//! 
const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;
const gfx = mach.gfx;

//  Configure clear, ....

//var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// Resources
//allocator: std.mem.Allocator,
frame_encoder: *gpu.CommandEncoder = undefined,
frame_render_pass: *gpu.RenderPassEncoder = undefined,

pub const name = .renderer;
pub const Mod = mach.Mod(@This());

pub const systems = .{
    .init = .{ .handler = init },
//    .deinit = .{ .handler = deinit },
    .begin_frame = .{ .handler = beginFrame },
    .end_frame = .{ .handler = endFrame },
};

// pub const components = .{
// };

fn init(
    self: *Mod
) !void {
    self.init(.{
//        .allocator = allocator,
    });
}
fn beginFrame(
    self: *Mod,
    core: *mach.Core.Mod,
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
}

