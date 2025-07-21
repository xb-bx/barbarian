package barbarian
import "vendor:nanovg"
import nvgl "vendor:nanovg/gl"
import "vendor:egl"
import gl "vendor:OpenGL"
import wl "wayland-odin/wayland"
import "core:fmt"
import "core:math"
MENU_MIN_WIDTH         :: 120
MENU_MAX_WIDTH         :: 500
MENU_MAX_ITEMS         :: 20
MENU_PADDING           :: 10
MENU_VPADDING          :: 4
MENU_TOPBOTTOM_PADDING :: 5
Menu :: struct {
    parent:       ^Monitor,
    state:        ^State,
    items:        ModuleMenu,
    hovered_item: int,
    selected_cb:  proc(data: rawptr, selected_index: int),
    cb_data:      rawptr,
    surface:      Surface,
    handler:      MouseHandler,
    item_height:  f32,
    rerender:     bool,
}
to_nvg_color :: proc(col: Color) -> nanovg.Color {
    return [4]f32 {
        f32(col.r)/255.0,
        f32(col.g)/255.0,
        f32(col.b)/255.0,
        f32(col.a)/255.0,
    }
}
menu_scroll :: proc(data: rawptr, state: ^State, dir: int) {}
menu_motion :: proc(data: rawptr, state: ^State, pos_x: f32, pos_y: f32) {
    menu := cast(^Menu)data
    new_hovered := int(pos_y / menu.item_height)
    menu.rerender = menu.hovered_item != new_hovered
    menu.hovered_item  = new_hovered
}
menu_click  :: proc(data: rawptr, state: ^State, btn: MouseButton, serial: u32) {
    menu := cast(^Menu)data
    if menu.hovered_item >= 0 && menu.hovered_item < len(menu.items.items) {
        menu.selected_cb(menu.cb_data, menu.hovered_item)
        menu_close(state)
    }
}
menu_init :: proc(menu: ^Menu, state: ^State, parent: ^Monitor, items: ModuleMenu, cb: proc(data: rawptr, index: int), cb_data: rawptr, nvg_ctx: ^nanovg.Context) {
    nanovg.FontSize(nvg_ctx, state.font_size)
    width := f32(MENU_MIN_WIDTH)
    height := f32(MENU_TOPBOTTOM_PADDING * 2)
    menu.state = state
    menu.handler.data   = menu
    menu.handler.motion = menu_motion
    menu.handler.scroll = menu_scroll
    menu.handler.click  = menu_click
    menu.item_height = state.font_size + MENU_VPADDING * 2
    for item in items.items {
        bounds: [4]f32 = {}
        nanovg.TextBounds(nvg_ctx, 0, 0, item.value, &bounds)
        new_width := bounds[2] - bounds[0] + MENU_PADDING * 2
        height += menu.item_height
        if new_width > width do width = new_width
    }
    if width > MENU_MAX_WIDTH do width = MENU_MAX_WIDTH
    menu.selected_cb = cb
    menu.cb_data = cb_data
    menu.items = items
    menu.hovered_item = -1
    menu.parent = parent
    surface_init_popup(&menu.surface, parent.output, state, parent.surface.layer_surface, int(math.ceil(width)), int(math.ceil(height)), int(state.mouse.pos_x - 5), int(state.mouse.pos_y-5))
    if (!egl.MakeCurrent(menu.state.rctx.display, menu.surface.egl_surface, menu.surface.egl_surface, menu.state.rctx.ctx)) {
        fmt.println("Error making current!")
        return
    }
    menu.surface.nvg_ctx = nvgl.Create({.DEBUG, .ANTI_ALIAS})
    nanovg.CreateFontMem(menu.surface.nvg_ctx, "sans", state.font, false)
    wl.display_roundtrip(state.display)
    menu.rerender = true
}
menu_render :: proc(menu: ^Menu) {
    fmt.println("RENDER MENU")
    menu.rerender = false
    ctx := menu.surface.nvg_ctx
    if (!egl.MakeCurrent(menu.state.rctx.display, menu.surface.egl_surface, menu.surface.egl_surface, menu.state.rctx.ctx)) {
        fmt.println("Error making current!")
        return
    }
    state := menu.state
    gl.ClearColor(f32(state.bg.r)/255.0, f32(state.bg.g)/255.0, f32(state.bg.b)/255.0, f32(state.bg.a)/255.0)
    gl.Clear(gl.COLOR_BUFFER_BIT)
    gl.Viewport(0, 0, i32(menu.surface.w), i32(menu.surface.h))
    nanovg.BeginFrame(ctx ,f32(menu.surface.w), f32(menu.surface.h), 1)
    defer nanovg.EndFrame(ctx)
    y := f32(MENU_TOPBOTTOM_PADDING)
    nanovg.TextAlign(ctx, .LEFT, .BASELINE)
    nanovg.FontSize(ctx, menu.state.font_size)
    nanovg.FontFace(ctx, "sans")
    for item,i in menu.items.items {
        text_color := to_nvg_color(menu.state.fg)
        bg_color   := to_nvg_color(menu.state.bg)
        bounds := [4]f32{}
        nanovg.TextBounds(ctx, 0, menu.item_height, item.value, &bounds)
        text_height := bounds[3] - bounds[1]

        if i == menu.hovered_item {
            text_color = to_nvg_color(menu.state.bg)
            bg_color   = to_nvg_color(menu.state.fg)
        } 
        nanovg.FillColor(ctx, bg_color)

        nanovg.BeginPath(ctx)
        nanovg.Rect(ctx, 0, y, f32(menu.surface.w), menu.item_height)
        nanovg.Fill(ctx)

        nanovg.FillColor(ctx, text_color)
        ypos := y + menu.item_height + (menu.item_height - text_height)/2 - bounds[1]
        nanovg.Text(ctx, MENU_PADDING, ypos, item.value)
        y += menu.item_height
    }
}

menu_close :: proc(state: ^State) {
    if state.menu != nil {
        menu_destroy(state.menu)
        free(state.menu)
        state.menu = nil
        wl.display_flush(state.display)
        wl.display_dispatch_pending(state.display)
    }
}
menu_destroy :: proc(menu: ^Menu) {
    nvgl.Destroy(menu.surface.nvg_ctx)
    surface_destroy(&menu.surface)
}
