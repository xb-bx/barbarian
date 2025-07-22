package barbarian
import "core:strings"
import "core:time"
import "core:fmt"
import wl "wayland-odin/wayland"

import gl "vendor:OpenGL"
import "vendor:egl"
import "vendor:nanovg"
import nvgl "vendor:nanovg/gl"
TOOLTIP_DELAY     :: time.Millisecond * 500
TOOLTIP_PAD       :: 4
TOOLTIP_MAX_WIDTH :: 500
Tooltip :: struct {
    text:          string, 
    module:        ^Module,
    text_width:    f32,
    text_height:   f32,
    text_baseline: f32,
    time:          time.Time,
    displayed:     bool,
    surface:       Surface,
    monitor:       ^Monitor,
    rerender:      bool,
}
tooltip_destroy :: proc(tooltip: ^Tooltip, state: ^State) {
    if tooltip == nil do return
    delete(tooltip.text)
    if tooltip.displayed {
        nvgl.Destroy(tooltip.surface.nvg_ctx)
        surface_destroy(&tooltip.surface)
        wl.display_flush(state.display)
        wl.display_dispatch_pending(state.display)
    }
    free(tooltip)
}
tooltip_render :: proc(tooltip: ^Tooltip, state: ^State) {
    ctx: ^nanovg.Context = nil 
    width  := tooltip.text_width  + TOOLTIP_PAD * 2 
    height := tooltip.text_height + TOOLTIP_PAD * 2
    if !tooltip.displayed {
        tooltip.displayed = true
        tooltip.surface.nvg_ctx = nvgl.Create({.DEBUG, .ANTI_ALIAS})
        ctx = tooltip.surface.nvg_ctx
        nanovg.CreateFontMem(ctx, "sans", state.font, false)
        pos_x  := tooltip.module.current_input.items.([]ModuleItem)[0].pos - PAD - 2
        mod_width := calculate_width(tooltip.module, ctx) + PAD * 2
        pos_x += (mod_width - width) / 2
        surface_init_popup(&tooltip.surface, tooltip.monitor.output, state, tooltip.monitor.surface.layer_surface, int(width), int(height), int(pos_x), int(f32(tooltip.monitor.surface.h) + 5))
    }
    ctx = tooltip.surface.nvg_ctx


    if (!egl.MakeCurrent(state.rctx.display, tooltip.surface.egl_surface, tooltip.surface.egl_surface, state.rctx.ctx)) {
        fmt.println("Error making current!")
        return
    }
    gl.ClearColor(f32(state.bg.r)/255.0, f32(state.bg.g)/255.0, f32(state.bg.b)/255.0, 1)
    gl.Clear(gl.COLOR_BUFFER_BIT)
    gl.Viewport(0, 0, i32(tooltip.surface.w), i32(tooltip.surface.h))
    {
        nanovg.BeginFrame(ctx, f32(tooltip.surface.w), f32(tooltip.surface.h), 1)
        defer nanovg.EndFrame(ctx)
        nanovg.BeginPath(ctx)
        nanovg.Rect(ctx, 0, 0, width, height)
        nanovg.StrokeColor(ctx, to_nvg_color(state.fg))
        nanovg.StrokeWidth(ctx, 2)
        nanovg.Stroke(ctx)

        nanovg.FontSize(ctx, state.font_size)
        nanovg.TextAlign(ctx, .LEFT, .BASELINE)
        text_pos_y := height + (height-tooltip.text_height)/2 + tooltip.text_baseline
        nanovg.Text(ctx, TOOLTIP_PAD, text_pos_y, tooltip.text)
    }
}
tooltip_get_time_to_show :: proc(tooltip: ^Tooltip) -> i32 {
    target := time.time_add(tooltip.time, TOOLTIP_DELAY)
    now := time.now()
    timeout := i32(time.duration_milliseconds(time.diff(now, target)))
    return timeout
}
tooltip_update_text :: proc(tooltip: ^Tooltip, text: string, ctx: ^nanovg.Context) {
    delete(tooltip.text)
    tooltip.rerender = true
    tooltip.text = strings.clone(text)
    bounds: [4]f32 = {}
    nanovg.TextAlign(ctx, .LEFT, .BASELINE)
    nanovg.TextBoxBounds(ctx, 0, 0, TOOLTIP_MAX_WIDTH, tooltip.text, &bounds)
    tooltip.text_width    = bounds[2] - bounds[0]
    tooltip.text_height   = bounds[3] - bounds[1]
    tooltip.text_baseline = bounds[1]
}
tooltip_init :: proc(tooltip: ^Tooltip, module: ^Module, monitor: ^Monitor, ctx: ^nanovg.Context) {
    tooltip.module = module
    tooltip_update_text(tooltip, module.current_input.tooltip.(string), ctx)
    tooltip.time = time.now()
    tooltip.monitor = monitor
}
