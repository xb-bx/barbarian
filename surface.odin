package barbarian
import "core:log"
import "core:c"
import "core:os"
import "vendor:egl"
import "vendor:nanovg"
import wl   "wayland-odin/wayland"
WAYLAND_BASE_SCALE :: 120

Surface :: struct {
    w:              int,
    h:              int,
    logical_w:      int,
    logical_h:      int,
    font_size:      f32,
    scale:          f32,
    wl_surface:     ^wl.wl_surface,
    egl_surface:    egl.Surface,
    egl_window:     ^wl.egl_window,
    layer_surface:  ^wl.zwlr_layer_surface_v1,
    wp_scale:          ^wl.wp_fractional_scale_v1,
    prefered_scale: int,
    viewport:       ^wl.wp_viewport,
    redraw:         bool,
    nvg_ctx:        ^nanovg.Context,
    state:          ^State,
    is_popup:       bool,
    xdg_surface:    ^wl.xdg_surface,
    xdg_popup:      ^wl.xdg_popup,
    xdg_positioner:^wl.xdg_positioner,
    swap:           bool,
    rescale:        bool,
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
        context = {}
        width := int(width)
        height := int(height)
        if surface.logical_w != width do surface.rescale = true
        if surface.logical_h != height do surface.rescale = true
        surface.logical_w = width
        surface.logical_h = height

    },
	popup_done = proc "c" (
		data: rawptr,
		xdg_popup: ^wl.xdg_popup,
	) {
        surface := cast(^Surface)data
        context = surface.state.ctx
        menu_close(surface.state)
    },
	repositioned = proc "c" (
		data: rawptr,
		xdg_popup: ^wl.xdg_popup,
		token: c.uint32_t,
	) {
        surface := cast(^Surface)data
        context = surface.state.ctx
    },
}
xdg_surface_listner := wl.xdg_surface_listener {
	configure = proc "c" (
		data: rawptr,
		xdg_surface: ^wl.xdg_surface,
		serial: c.uint32_t,
	) {
        wl.xdg_surface_ack_configure(xdg_surface, serial)
    },

}
layer_listener:  wl.zwlr_layer_surface_v1_listener = {
    configure = proc "c" (
        data: rawptr,
        zwlr_layer_surface_v1: ^wl.zwlr_layer_surface_v1,
        serial: c.uint32_t,
        width: c.uint32_t,
        height: c.uint32_t,
    ) {
        surface := cast(^Surface)data
        context = surface.state.ctx
        wl.zwlr_layer_surface_v1_ack_configure(zwlr_layer_surface_v1, serial)
        width := int(width)
        height := int(height)
        if surface.logical_w != width do surface.rescale = true
        if surface.logical_h != height do surface.rescale = true
        log.debugf("layer configure: %dx%d -> %dx%d", surface.logical_w, surface.logical_h, width, height)
        surface.logical_w = width
        surface.logical_h = height
        
    },
    closed = proc "c" (
        data: rawptr,
        zwlr_layer_surface_v1: ^wl.zwlr_layer_surface_v1,
    ) {

    },
}
surface_init_regular :: proc(surface: ^Surface, output: ^wl.wl_output, state: ^State) {
    surface.layer_surface = wl.zwlr_layer_shell_v1_get_layer_surface(state.layer_shell, surface.wl_surface, output, wl.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM, "wb")
    wl.zwlr_layer_surface_v1_set_size(surface.layer_surface, 0, u32(surface.logical_h))
    wl.zwlr_layer_surface_v1_set_exclusive_zone(surface.layer_surface, i32(surface.logical_h))
    wl.zwlr_layer_surface_v1_set_anchor(surface.layer_surface, wl.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | wl.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | wl.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT)

    wl.zwlr_layer_surface_v1_set_keyboard_interactivity(surface.layer_surface, wl.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND)
    wl.zwlr_layer_surface_v1_add_listener(surface.layer_surface, &layer_listener, surface)
}
surface_init_popup :: proc(surface: ^Surface, state: ^State, opts: PopupSurface) {
    surface.is_popup = true

    surface.xdg_surface    = wl.xdg_wm_base_get_xdg_surface(state.xdg_wm_base, surface.wl_surface) 
    surface.xdg_positioner = wl.xdg_wm_base_create_positioner(state.xdg_wm_base)
    surface.prefered_scale = opts.parent_scale

    surface.scale = f32(surface.prefered_scale) / f32(WAYLAND_BASE_SCALE)
    surface.w = (surface.logical_w * surface.prefered_scale + 119) / WAYLAND_BASE_SCALE
    surface.h = (surface.logical_h * surface.prefered_scale + 119) / WAYLAND_BASE_SCALE

    wl.xdg_positioner_set_size(surface.xdg_positioner, i32(surface.logical_w), i32(surface.logical_h))
    wl.xdg_positioner_set_anchor_rect(surface.xdg_positioner, 0, 0, i32(surface.logical_w), i32(surface.logical_h))
    wl.xdg_positioner_set_anchor(surface.xdg_positioner, wl.XDG_POSITIONER_ANCHOR_TOP_LEFT)
    wl.xdg_positioner_set_gravity(surface.xdg_positioner, wl.XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT)
    wl.xdg_positioner_set_offset(surface.xdg_positioner, i32(opts.x), i32(opts.y))
    wl.xdg_positioner_set_constraint_adjustment(surface.xdg_positioner, 0)

    surface.xdg_popup = wl.xdg_surface_get_popup(surface.xdg_surface, nil, surface.xdg_positioner)
    wl.display_roundtrip(state.display)
    wl.zwlr_layer_surface_v1_get_popup(opts.parent, surface.xdg_popup)
    wl.xdg_surface_add_listener(surface.xdg_surface, &xdg_surface_listner, surface)
    wl.xdg_popup_add_listener(surface.xdg_popup, &xdg_popup_listener, surface)
}
LayerSurface :: struct{}
PopupSurface :: struct {
    x:      int,
    y:      int,
    parent: ^wl.zwlr_layer_surface_v1,
    parent_scale: int
}
SurfaceOpts :: union {
    LayerSurface,
    PopupSurface,
}
scale_listener := wl.wp_fractional_scale_v1_listener {
    preferred_scale = proc "c" (data: rawptr, wp_scale: ^wl.wp_fractional_scale_v1, scale: c.uint32_t) {
        surface := (cast(^Surface)data)
        scale := int(surface.prefered_scale)
        surface.rescale = surface.prefered_scale != scale
        surface.prefered_scale = scale
    } 
}
surface_init :: proc(surface: ^Surface, output: ^wl.wl_output, state: ^State, w: int, h: int, surface_opts: SurfaceOpts) {
    surface.w = w
    surface.h = h
    surface.logical_w = w
    surface.logical_h = h
    surface.prefered_scale = WAYLAND_BASE_SCALE
    surface.font_size = state.font_size
    surface.scale = 1

    surface.wl_surface = wl.wl_compositor_create_surface(state.compositor)
    surface.state = state
    switch opts in surface_opts {
    case LayerSurface:
        surface_init_regular(surface, output, state)
    case PopupSurface:
        surface_init_popup(surface, state, opts)
    }
    wl.wl_surface_commit(surface.wl_surface)

    surface.egl_window = wl.egl_window_create(surface.wl_surface, i32(surface.w), i32(surface.h))
    surface.egl_surface = egl.CreateWindowSurface(
        state.rctx.display,
        state.rctx.config,
        egl.NativeWindowType(surface.egl_window),
        nil,
    )
    if surface.egl_surface == egl.NO_SURFACE {
        panic("Error creating window surface")
    }
    surface.wp_scale = wl.wp_fractional_scale_manager_v1_get_fractional_scale(state.scale_manager, surface.wl_surface)
    wl.wp_fractional_scale_v1_add_listener(surface.wp_scale, &scale_listener, surface)
    wl.display_roundtrip(state.display)
    surface.viewport = wl.wp_viewporter_get_viewport(state.viewporter, surface.wl_surface)
    wl.wp_viewport_set_destination(surface.viewport, i32(surface.logical_w), i32(surface.logical_h))
    wl.display_roundtrip(state.display)
    if surface.rescale do surface_rescale(surface)
    surface.swap = true
}
surface_rescale :: proc (surface: ^Surface) {
    surface.scale = f32(surface.prefered_scale) / f32(WAYLAND_BASE_SCALE)
    surface.w = (surface.logical_w * surface.prefered_scale + 119) / WAYLAND_BASE_SCALE
    surface.h = (surface.logical_h * surface.prefered_scale + 119) / WAYLAND_BASE_SCALE
    wl.egl_window_resize(surface.egl_window, i32(surface.w), i32(surface.h), 0, 0)
    if surface.xdg_positioner != nil {
        wl.xdg_positioner_set_size(surface.xdg_positioner, i32(surface.logical_w), i32(surface.logical_h))
        wl.xdg_positioner_set_anchor_rect(surface.xdg_positioner, 0, 0, i32(surface.logical_w), i32(surface.logical_h))
    } else {
        wl.zwlr_layer_surface_v1_set_exclusive_zone(surface.layer_surface, i32(surface.logical_h))
    }
    wl.wp_viewport_set_destination(surface.viewport, i32(surface.logical_w), i32(surface.logical_h))
    wl.wl_surface_commit(surface.wl_surface)
    surface.rescale = false
    surface.redraw = true
}
frame_listener := wl.wl_callback_listener {
	done = proc "c" (data: rawptr, wl_callback: ^wl.wl_callback, callback_data: c.uint32_t) {
        wl.wl_callback_destroy(wl_callback)
        surface := cast(^Surface)data
        context = surface.state.ctx
        surface.swap = true 
    },
}
surface_create_frame_callback :: proc(surface: ^Surface) {
    callback := wl.wl_surface_frame(surface.wl_surface)
    wl.wl_callback_add_listener(callback, &frame_listener, surface)
}
surface_swap :: proc(surface: ^Surface) {
    state := surface.state
    if (!egl.MakeCurrent(state.rctx.display, surface.egl_surface, surface.egl_surface, state.rctx.ctx)) {
        panic("Error making current")
    }
    egl.SwapBuffers(state.rctx.display, surface.egl_surface)
    surface_create_frame_callback(surface)
    wl.wl_surface_damage(surface.wl_surface, 0, 0, i32(surface.logical_w), i32(surface.logical_h))
    wl.wl_surface_damage_buffer(surface.wl_surface, 0, 0, i32(surface.w), i32(surface.h))
    wl.wl_surface_commit(surface.wl_surface)
    surface.swap = false
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
    wl.wp_viewport_destroy(surface.viewport)
    wl.wp_fractional_scale_v1_destroy(surface.wp_scale)
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
