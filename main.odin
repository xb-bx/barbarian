package barbarian

import "core:mem"
import "core:encoding/json"
import "core:math"
import "core:c"
import "core:strings"
import "core:os"
import "core:time"
import "core:time/datetime"
import "core:c/libc"
import "core:fmt"
import "core:flags"
import "core:slice"
import "wayland-odin/render"
import "wayland-odin/utils"
import wl "wayland-odin/wayland"

import "core:sys/posix"

import "base:runtime"
import gl "vendor:OpenGL"
import "vendor:egl"
import "vendor:fontstash"
import "vendor:nanovg"
import nvgl "vendor:nanovg/gl"
Mouse :: struct {
    pos_x:  f32,
    pos_y:  f32,
    handler: ^MouseHandler,
}
State :: struct {
    display:     ^wl.wl_display,
    compositor:  ^wl.wl_compositor,
    layer_shell: ^wl.zwlr_layer_shell_v1,
    shm:         ^wl.wl_shm,
    seat:        ^wl.wl_seat,
    monitors:    [dynamic]^Monitor,
    ctx:         runtime.Context,
    rctx:        render.RenderContext,
    xdg_wm_base: ^wl.xdg_wm_base,
    mouse:       Mouse,
    bg:          Color,
    fg:          Color,
    tooltip_bg:  Color,
    tooltip_fg:  Color,
    menu_bg:     Color,
    menu_fg:     Color,
    menu:        ^Menu,
    font:        []byte,
    font_size:   f32,
    height:      f32,
    tooltip:     ^Tooltip,
}
MouseHandler :: struct {
    data: rawptr,
    motion: proc(data: rawptr, state: ^State, pos_x: f32, pos_y: f32),
    click: proc(data: rawptr, state: ^State, btn: MouseButton, serial: u32),
    scroll: proc(data: rawptr, state: ^State, dir: int),
}

pixel :: struct {
    b: u8,
    g: u8,
    r: u8,
    a: u8,
}
output_geometry :: proc "c" (
    data: rawptr,
    wl_output: ^wl.wl_output,
    x: c.int32_t,
    y: c.int32_t,
    physical_width: c.int32_t,
    physical_height: c.int32_t,
    subpixel: c.int32_t,
    make: cstring,
    model: cstring,
    transform: c.int32_t,
) {
    st := transmute(^State)data
    context = st.ctx
    monitor := get_or_create_monitor_for_output(st, wl_output)
}

output_mode :: proc "c" (
    data: rawptr,
    wl_output: ^wl.wl_output,
    flags: c.uint32_t,
    width: c.int32_t,
    height: c.int32_t,
    refresh: c.int32_t,
) {
    st := transmute(^State)data
    context = st.ctx
    monitor := get_or_create_monitor_for_output(st, wl_output)
    monitor.surface.w = int(width)
    monitor.surface.h = int(st.height)
}
output_done  :: proc "c" (data: rawptr, wl_output: ^wl.wl_output) {
    st := transmute(^State)data
    context = st.ctx
    monitor := get_or_create_monitor_for_output(st, wl_output)
    //monitor.refresh_surface = true
}
output_scale :: proc "c" (data: rawptr, wl_output: ^wl.wl_output, factor: c.int32_t) {
    st := transmute(^State)data
    context = st.ctx
    monitor := get_or_create_monitor_for_output(st, wl_output)
    monitor.surface.scale = int(factor)
}
output_name  :: proc "c" (data: rawptr, wl_output: ^wl.wl_output, name: cstring) {
    st := transmute(^State)data
    context = st.ctx
    monitor := get_or_create_monitor_for_output(st, wl_output)
    monitor.name = strings.clone_from_cstring(name)
    fmt.println("output:", name)
}
output_description :: proc "c" (data: rawptr, wl_output: ^wl.wl_output, description: cstring) {

}
main_output: ^wl.wl_output = nil
output_listener: wl.wl_output_listener = {
    geometry    = output_geometry,
    mode        = output_mode,
    description = output_description,
    done        = output_done,
    name        = output_name,
    scale       = output_scale,
}
wl_fixed_to_double :: proc(f: wl.wl_fixed_t) -> f64 {
    u: struct #raw_union {
        d: f64,
        i: i64,
    }
    u.i = ((1023 + 44) << 52) + (1 << 51) + i64(f)
    return u.d - f64(3 << 43)
}
wl_fixed_from_double :: proc(d: f64) -> wl.wl_fixed_t {
    u: struct #raw_union {
        d: f64,
        i: i64,
    }

    u.d = d + f64(3 << (51 - 8))
    return wl.wl_fixed_t(u.i)
}
MouseButton :: enum {
    Left   = 272,
    Right  = 273,
    Middle = 274,
}
pointer_listener: wl.wl_pointer_listener = {
    enter = proc "c" (
        data: rawptr,
        wl_pointer: ^wl.wl_pointer,
        serial: c.uint32_t,
        surface: ^wl.wl_surface,
        surface_x: wl.wl_fixed_t,
        surface_y: wl.wl_fixed_t,
    ) {
        state: ^State = cast(^State)data
        context = state.ctx
        mon := get_monitor_by_surface(state, surface)
        if mon != nil {
            state.mouse.handler = &mon.mouse_handler
        } else {
            if state.menu != nil {
                state.mouse.handler = &state.menu.handler
            }
        }

    },
    leave = proc "c" (
        data: rawptr,
        wl_pointer: ^wl.wl_pointer,
        serial: c.uint32_t,
        surface: ^wl.wl_surface,
    ) {
        state: ^State = cast(^State)data
        context = state.ctx
        state.mouse.handler = nil
        tooltip_destroy(state.tooltip, state)
        state.tooltip = nil
    },
    motion = proc "c" (
        data: rawptr,
        wl_pointer: ^wl.wl_pointer,
        time: c.uint32_t,
        surface_x: wl.wl_fixed_t,
        surface_y: wl.wl_fixed_t,
    ) {
        state: ^State = cast(^State)data
        context = state.ctx
        state.mouse.pos_x = f32(wl_fixed_to_double(surface_x))
        state.mouse.pos_y = f32(wl_fixed_to_double(surface_y))
        state.mouse.handler.motion(state.mouse.handler.data, state, state.mouse.pos_x, state.mouse.pos_y)
    },
    button = proc "c" (
        data: rawptr,
        wl_pointer: ^wl.wl_pointer,
        serial: c.uint32_t,
        time: c.uint32_t,
        button: c.uint32_t,
        state: c.uint32_t,
    ) {
        st := cast(^State)data
        btn := MouseButton(button)
        context = st.ctx
        if state == 0 && st.mouse.handler != nil {
            st.mouse.handler.click(st.mouse.handler.data, st, btn, serial)
        }
    },
    axis = proc "c" (
        data: rawptr,
        wl_pointer: ^wl.wl_pointer,
        time: c.uint32_t,
        axis: c.uint32_t,
        value: wl.wl_fixed_t,
    ) {
        st := cast(^State)data
        context = st.ctx
        if st.mouse.handler != nil {
            dir := 0
            if value > 0 do dir = 1
            if value < 0 do dir = -1
            st.mouse.handler.scroll(st.mouse.handler.data, st, dir)
        }
    },
    axis_source = proc "c" (
        data: rawptr,
        wl_pointer: ^wl.wl_pointer,
        axis_source: c.uint32_t,
    ) {
    },
	axis_stop = proc "c" (
		data: rawptr,
		wl_pointer: ^wl.wl_pointer,
		time: c.uint32_t,
		axis: c.uint32_t,
	) {
    },
	axis_discrete = proc "c" (
		data: rawptr,
		wl_pointer: ^wl.wl_pointer,
		axis: c.uint32_t,
		discrete: c.int32_t,
	) {
    },
	axis_value120 = proc "c" (
		data: rawptr,
		wl_pointer: ^wl.wl_pointer,
		axis: c.uint32_t,
		value120: c.int32_t,
	) {
    },
	axis_relative_direction = proc "c" (
		data: rawptr,
		wl_pointer: ^wl.wl_pointer,
		axis: c.uint32_t,
		direction: c.uint32_t,
	) {
    },
    
    frame = proc "c" (data: rawptr, wl_pointer: ^wl.wl_pointer) {}
}
seat_listener: wl.wl_seat_listener = {
    capabilities = proc "c" (data: rawptr, wl_seat: ^wl.wl_seat, capabilities: c.uint32_t) {
        state: ^State = cast(^State)data
        context = state.ctx
        if capabilities & wl.WL_SEAT_CAPABILITY_POINTER > 0 {
            pointer := wl.wl_seat_get_pointer(wl_seat)
            wl.wl_pointer_add_listener(pointer, &pointer_listener, data)
        } 
    }, 
    name = proc "c" (data: rawptr, wl_seat: ^wl.wl_seat, name: cstring) {
        context = runtime.default_context()
        fmt.println("seat name:", name)
    }

}
xdg_listener := wl.xdg_wm_base_listener {
    ping = proc "c" (
		data: rawptr,
		xdg_wm_base: ^wl.xdg_wm_base,
		serial: c.uint32_t,
	) {
        wl.xdg_wm_base_pong(xdg_wm_base, serial)
    }
}
global :: proc "c" (
    data: rawptr,
    registry: ^wl.wl_registry,
    name: c.uint32_t,
    interface: cstring,
    version: c.uint32_t,
) {
    state: ^State = cast(^State)data
    context = state.ctx
    fmt.println("inteface", interface)
    if interface == wl.wl_compositor_interface.name {
        state.compositor =
        cast(^wl.wl_compositor)(wl.wl_registry_bind(
                registry,
                name,
                &wl.wl_compositor_interface,
                version,
            ))
    }

    if interface == wl.wl_shm_interface.name {
        state.shm =
        cast(^wl.wl_shm)(wl.wl_registry_bind(registry, name, &wl.wl_shm_interface, version))
    }
    if interface == wl.wl_output_interface.name {
        main_output = cast(^wl.wl_output)wl.wl_registry_bind(registry, name, &wl.wl_output_interface, version)
        wl.wl_output_add_listener(main_output, &output_listener, state)
    }
    if interface == wl.wl_seat_interface.name {
        state.seat = cast(^wl.wl_seat)wl.wl_registry_bind(registry, name, &wl.wl_seat_interface, version)
        wl.wl_seat_add_listener(state.seat, &seat_listener, state)
    }
    if interface == wl.xdg_wm_base_interface.name {
        state.xdg_wm_base = cast(^wl.xdg_wm_base)wl.wl_registry_bind(registry, name, &wl.xdg_wm_base_interface, version)
        wl.xdg_wm_base_add_listener(state.xdg_wm_base, &xdg_listener, state)
    }

    if interface == wl.zwlr_layer_shell_v1_interface.name {
        state.layer_shell =
        cast(^wl.zwlr_layer_shell_v1)(wl.wl_registry_bind(
                registry,
                name,
                &wl.zwlr_layer_shell_v1_interface,
                version,
            ))
    }
}

global_remove :: proc "c" (data: rawptr, registry: ^wl.wl_registry, name: c.uint32_t) {
    context = runtime.default_context()
    fmt.println("remove")
}

registry_listener := wl.wl_registry_listener {
    global        = global,
    global_remove = global_remove,
}


buffer_listener := wl.wl_buffer_listener {
    release = proc "c" (data: rawptr, wl_buffer: ^wl.wl_buffer) {
        wl.wl_buffer_destroy(wl_buffer)
    },
}

w: int = 0
h: int = 0
layer_listener:  wl.zwlr_layer_surface_v1_listener = {
    configure = proc "c" (
        data: rawptr,
        zwlr_layer_surface_v1: ^wl.zwlr_layer_surface_v1,
        serial: c.uint32_t,
        width: c.uint32_t,
        height: c.uint32_t,
    ) {
        context = runtime.default_context()
        w = int(width)
        h = int(height)
        fmt.println("configure", w, h)
        wl.zwlr_layer_surface_v1_ack_configure(zwlr_layer_surface_v1, serial)
        
    },
    closed = proc "c" (
        data: rawptr,
        zwlr_layer_surface_v1: ^wl.zwlr_layer_surface_v1,
    ) {

    }
}
prepare_poll_fds :: proc(pollfds: ^[dynamic]posix.pollfd, state: ^State) {
    clear(pollfds)
    append(pollfds, posix.pollfd { fd = posix.FD(state.display.fd), events = {.IN} })
    for monitor in state.monitors {
        mon_iter := MonitorIterator {monitor = monitor}
        for mod in monitor_iter(&mon_iter) {
            mod.pollfd_index = len(pollfds)
            append(pollfds, posix.pollfd { fd = mod.pipe_out, events = {.IN, .OUT} })
        }
    }
}
PAD :: 3.5
CliOpts :: struct {
    config_path: string `usage:"Set config path"`,
} 
main :: proc() {
    opts: CliOpts = {}
    flags.parse_or_exit(&opts, os.args, .Unix)
    state: State = {}
    state.ctx = context
    cfg, err := load_config(opts.config_path)
    if err != nil {
        fmt.eprintln("ERROR while loading config:", err)
        os.exit(1)
    }
    fontdata, os_err := os.read_entire_file_or_err(cfg.font)
    if os_err != nil {
        fmt.eprintln("ERROR while loading font:", os_err)
        os.exit(1)
    }
    state.height = cfg.height
    state.font = fontdata
    state.font_size = cfg.font_size
    color_ok := false
    state.bg, color_ok = hex_to_color(cfg.background)
    if !color_ok do state.bg = Color { 0, 0, 0, 0xFF }
    state.fg, color_ok = hex_to_color(cfg.foreground)
    if !color_ok do state.fg = Color { 0xFF, 0xFF, 0xFF, 0xFF }

    state.tooltip_bg, color_ok = hex_to_color(cfg.tooltip_background)
    if !color_ok do state.tooltip_bg = state.bg
    state.tooltip_fg, color_ok = hex_to_color(cfg.tooltip_foreground)
    if !color_ok do state.tooltip_fg = state.fg

    state.menu_bg, color_ok = hex_to_color(cfg.menu_background)
    if !color_ok do state.menu_bg = state.bg
    state.menu_fg, color_ok = hex_to_color(cfg.menu_foreground)
    if !color_ok do state.menu_fg = state.fg


    display := wl.display_connect(nil)
    state.display = display
    registry := wl.wl_display_get_registry(display)

    wl.wl_registry_add_listener(registry, &registry_listener, &state)
    wl.display_roundtrip(display)
    for len(state.monitors) == 0 {
        wl.display_roundtrip(display)
        time.sleep(10 * time.Millisecond)
    }
    wl.display_roundtrip(display)
    fmt.println(len(state.monitors), "outputs")

    state.rctx = init_egl(display)
    gl.load_up_to(int(4), 5, egl.gl_set_proc_address)
    for monitor in state.monitors {
        surface_init(&monitor.surface, monitor.output, &state, monitor.surface.w, monitor.surface.h)
    }
    wl.display_roundtrip(display)


    for monitor in state.monitors {
        if (!egl.MakeCurrent(state.rctx.display, monitor.surface.egl_surface, monitor.surface.egl_surface, state.rctx.ctx)) {
            fmt.println("Error making current!")
            return
        }
        monitor.surface.nvg_ctx = nvgl.Create({.DEBUG, .ANTI_ALIAS})
        nanovg.CreateFontMem(monitor.surface.nvg_ctx, "sans", state.font, false)
        monitor.surface.redraw = true
    }
    wl.display_roundtrip(display)
    for output, out_config in cfg.outputs {
        monitor := get_monitor_by_name(&state, output) 
        if monitor == nil do fmt.eprintln("WARN: No output", output)
        init_modules :: proc(modules_out: ^[]Module, cfg: ^Config, modules: []string) {
            mods := make([dynamic]Module)
            for module in modules {
                mod_cfg, ok := cfg.modules[module]
                if !ok { 
                    fmt.eprintln("ERROR: No module", module)
                    continue
                }
                append(&mods, Module {
                    exec      = mod_cfg.exec,
                    clickable = mod_cfg.clickable,
                    min_width = mod_cfg.min_width,
                })
            }
            modules_out ^= mods[:]
            for &mod in modules_out^ {
                err := run_module(&mod)
                if err != nil do fmt.eprintln("ERROR: Failed to run module", mod.exec)
            }
        }
        init_modules(&monitor.left, cfg, out_config.modules_left)
        init_modules(&monitor.right, cfg, out_config.modules_right)
    }
    pollfds := make([dynamic]posix.pollfd)
    wl.display_roundtrip(display)
    for {
        if state.menu != nil && state.menu.rerender {
            menu_render(state.menu)
            egl.SwapBuffers(state.rctx.display, state.menu.surface.egl_surface)
            wl.wl_surface_damage_buffer(state.menu.surface.wl_surface, 0, 0, i32(state.menu.surface.w), i32(state.menu.surface.h))
            wl.wl_surface_commit(state.menu.surface.wl_surface)
            wl.display_flush(display)
            wl.display_dispatch_pending(display)
        }
        if state.tooltip != nil && (state.tooltip.rerender || !state.tooltip.displayed) && tooltip_get_time_to_show(state.tooltip) <= 0 {
            tooltip_render(state.tooltip, &state)
            egl.SwapBuffers(state.rctx.display, state.tooltip.surface.egl_surface)
            wl.wl_surface_damage_buffer(state.tooltip.surface.wl_surface, 0, 0, i32(state.tooltip.surface.w), i32(state.tooltip.surface.h))
            wl.wl_surface_commit(state.tooltip.surface.wl_surface)
            wl.display_flush(display)
            wl.display_dispatch_pending(display)

        }
        for monitor in state.monitors {
            if monitor.surface.redraw {
                if (!egl.MakeCurrent(state.rctx.display, monitor.surface.egl_surface, monitor.surface.egl_surface, state.rctx.ctx)) {
                    fmt.println("Error making current!")
                    return
                }
                {
                    gl.ClearColor(f32(state.bg.r)/255.0, f32(state.bg.g)/255.0, f32(state.bg.b)/255.0, f32(state.bg.a)/255.0)
                    gl.Clear(gl.COLOR_BUFFER_BIT)
                    gl.Viewport(0, 0, i32(monitor.surface.w), i32(monitor.surface.h))
                    ctx := monitor.surface.nvg_ctx
                    nanovg.BeginFrame(ctx, f32(monitor.surface.w), f32(monitor.surface.h), 1)
                    defer nanovg.EndFrame(ctx)
                    nanovg.FontSize(ctx, state.font_size)
                    nanovg.FontFaceId(ctx, 0)
                    x := f32(0)
                    for &mod, i in monitor.left {
                        if mod.current_input.items == nil do continue
                        x = module_render(&mod, &state, ctx, x)
                        if i != len(monitor.left) - 1 {
                            nanovg.BeginPath(ctx)
                            nanovg.FillColor(ctx, nanovg.RGBA(255,255,255,255))
                            nanovg.Rect(ctx, x, 0, 1, state.height)
                            nanovg.Fill(ctx)
                            x+=2
                        }
                    }
                    x = f32(monitor.surface.w)
                    #reverse for &mod, i in monitor.right {
                        x -= calculate_width(&mod, ctx)
                        module_render(&mod, &state, ctx, x)
                        if i != 0 {
                            x-=2
                            nanovg.BeginPath(ctx)
                            nanovg.FillColor(ctx, nanovg.RGBA(255,255,255,255))
                            nanovg.Rect(ctx, x, 0, 1, state.height)
                            nanovg.Fill(ctx)
                        }
                    }
                    
                    
                }


                egl.SwapBuffers(state.rctx.display, monitor.surface.egl_surface)
                wl.wl_surface_damage_buffer(monitor.surface.wl_surface, 0, 0, i32(monitor.surface.w), i32(monitor.surface.h))
                wl.wl_surface_commit(monitor.surface.wl_surface)
                monitor.surface.redraw = false
                wl.display_flush(display)
            }
        }

        prepare_poll_fds(&pollfds, &state)
        timeout := i32(-1)
        if state.tooltip != nil {
            timeout = tooltip_get_time_to_show(state.tooltip)
            if timeout < 0 do timeout = -1
        }
        res := posix.poll(slice.as_ptr(pollfds[:]), u32(len(pollfds)), timeout)

        for monitor in state.monitors {
            mon_iter := MonitorIterator {monitor = monitor}
            for mod in monitor_iter(&mon_iter) {
                if .IN in pollfds[mod.pollfd_index].revents {
                    process_input(mod, &state)
                }
                if mod.redraw {
                    mod.redraw = false
                    monitor.surface.redraw = true
                }
            }
        }
        if .IN in pollfds[0].revents {
            wl.display_dispatch(display)
        }
    }
}

