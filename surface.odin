package barbarian
import "core:fmt"
import "core:c"
import "core:os"
import wl "wayland-odin/wayland"
import gl "vendor:OpenGL"
import "vendor:egl"
import "vendor:nanovg"
import nvgl "vendor:nanovg/gl"

Surface :: struct {
    w:             int,
    h:             int,
    wl_surface:    ^wl.wl_surface,
    egl_surface:   egl.Surface,
    egl_window:    ^wl.egl_window,
    layer_surface: ^wl.zwlr_layer_surface_v1,
    scale:         int,
    redraw:        bool,
    nvg_ctx:       ^nanovg.Context,
    state:         ^State,
    is_popup:      bool,
    xdg_surface:   ^wl.xdg_surface,
    xdg_popup:     ^wl.xdg_popup,
    xdg_positioner:^wl.xdg_positioner,

}
xdg_popup_listener := wl.xdg_popup_listener {
	configure = proc "c" (
		data: rawptr,
		xdg_popup: ^wl.xdg_popup,
		x: c.int32_t,
		y: c.int32_t,
		width: c.int32_t,
		height: c.int32_t,
	) {
        surface := cast(^Surface)data
        context = surface.state.ctx
        fmt.println("popup_configure", x, y, width, height)
    },
	popup_done = proc "c" (
		data: rawptr,
		xdg_popup: ^wl.xdg_popup,
	) {
        surface := cast(^Surface)data
        context = surface.state.ctx
        fmt.println("done")
        menu_close(surface.state)
    },
	repositioned = proc "c" (
		data: rawptr,
		xdg_popup: ^wl.xdg_popup,
		token: c.uint32_t,
	) {
        surface := cast(^Surface)data
        context = surface.state.ctx
        fmt.println("repos", token)
    }
}
xdg_surface_listner := wl.xdg_surface_listener {
	configure = proc "c" (
		data: rawptr,
		xdg_surface: ^wl.xdg_surface,
		serial: c.uint32_t,
	) {
        wl.xdg_surface_ack_configure(xdg_surface, serial)
    }
}
surface_init_popup :: proc(surface: ^Surface, output: ^wl.wl_output, state: ^State, parent: ^wl.zwlr_layer_surface_v1, w: int, h: int, pos_x: int, pos_y: int) {
    surface.w = w
    surface.h = h
    surface.wl_surface = wl.wl_compositor_create_surface(state.compositor)
    surface.state    = state
    surface.is_popup = true

    surface.xdg_surface    = wl.xdg_wm_base_get_xdg_surface(state.xdg_wm_base, surface.wl_surface) 
    surface.xdg_positioner = wl.xdg_wm_base_create_positioner(state.xdg_wm_base)

    fmt.println("pw:ph", i32(w), i32(h))
    wl.xdg_positioner_set_size(surface.xdg_positioner, i32(w), i32(h))
    wl.xdg_positioner_set_anchor_rect(surface.xdg_positioner, 0, 0, i32(w), i32(h))
    wl.xdg_positioner_set_anchor(surface.xdg_positioner, wl.XDG_POSITIONER_ANCHOR_TOP_LEFT)
    wl.xdg_positioner_set_gravity(surface.xdg_positioner, wl.XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT)
    wl.xdg_positioner_set_offset(surface.xdg_positioner, i32(pos_x), i32(pos_y))
    wl.xdg_positioner_set_constraint_adjustment(surface.xdg_positioner, 0)

    surface.xdg_popup      = wl.xdg_surface_get_popup(surface.xdg_surface, nil, surface.xdg_positioner)
    wl.display_roundtrip(state.display)
    wl.zwlr_layer_surface_v1_get_popup(parent, surface.xdg_popup)
    wl.xdg_surface_add_listener(surface.xdg_surface, &xdg_surface_listner, surface)
    wl.xdg_popup_add_listener(surface.xdg_popup, &xdg_popup_listener, surface)

    wl.display_roundtrip(state.display)
    wl.wl_surface_commit(surface.wl_surface)
    surface.egl_window = wl.egl_window_create(surface.wl_surface, i32(w), i32(h))
    surface.egl_surface = egl.CreateWindowSurface(
        state.rctx.display,
        state.rctx.config,
        egl.NativeWindowType(surface.egl_window),
        nil,
    )
    if surface.egl_surface == egl.NO_SURFACE {
        fmt.println("Error creating window surface")
        os.exit(1)
    }
    wl.display_roundtrip(state.display)
}
surface_init :: proc(surface: ^Surface, output: ^wl.wl_output, state: ^State, w: int, h: int) {
    surface.w = w
    surface.h = h
    surface.wl_surface = wl.wl_compositor_create_surface(state.compositor)
    surface.state = state

    surface.layer_surface = wl.zwlr_layer_shell_v1_get_layer_surface(state.layer_shell, surface.wl_surface, output, wl.ZWLR_LAYER_SHELL_V1_LAYER_TOP, "wb")
    wl.zwlr_layer_surface_v1_set_size(surface.layer_surface, u32(w), u32(h))
    wl.zwlr_layer_surface_v1_set_exclusive_zone(surface.layer_surface, i32(h))
    wl.zwlr_layer_surface_v1_set_anchor(surface.layer_surface, wl.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP)

    wl.zwlr_layer_surface_v1_set_keyboard_interactivity(surface.layer_surface, wl.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND)
    wl.zwlr_layer_surface_v1_add_listener(surface.layer_surface, &layer_listener, nil)

    wl.wl_surface_commit(surface.wl_surface)
    wl.display_roundtrip(state.display)
    surface.egl_window = wl.egl_window_create(surface.wl_surface, i32(w), i32(h))
    surface.egl_surface = egl.CreateWindowSurface(
        state.rctx.display,
        state.rctx.config,
        egl.NativeWindowType(surface.egl_window),
        nil,
    )
    if surface.egl_surface == egl.NO_SURFACE {
        fmt.println("Error creating window surface")
        os.exit(1)
    }
}
surface_destroy :: proc(surface: ^Surface) {
    wl.wl_surface_attach(surface.wl_surface, nil, 0, 0)
    wl.wl_surface_commit(surface.wl_surface)
    if !egl.MakeCurrent(surface.state.rctx.display, egl.NO_SURFACE, egl.NO_SURFACE, egl.NO_CONTEXT) {
        panic("cant egl.MakeCurrent")
    }
    if !egl.DestroySurface(surface.state.rctx.display, surface.egl_surface) {
        panic("cant egl.DestroySurface")
    }
    wl.egl_window_destroy(surface.egl_window)
    if surface.is_popup {
        wl.xdg_positioner_destroy(surface.xdg_positioner)
        wl.xdg_popup_destroy(surface.xdg_popup)
        wl.xdg_surface_destroy(surface.xdg_surface)
        
    } else {
        wl.zwlr_layer_surface_v1_destroy(surface.layer_surface)
    }
    wl.wl_surface_destroy(surface.wl_surface)
}
