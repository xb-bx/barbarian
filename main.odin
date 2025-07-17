package barbarian

import "core:c"
import "core:os"
import "core:time"
import "core:c/libc"
import "core:fmt"
import "core:slice"
import "wayland-odin/render"
import "wayland-odin/utils"
import wl "wayland-odin/wayland"

import "core:sys/posix"

import "base:runtime"
import gl "vendor:OpenGL"
import "vendor:egl"
//import textrender "odin-text-renderer/text-renderer"
//import sdl_ttf "vendor:sdl2/ttf"
import "vendor:fontstash"
import "vendor:nanovg"
import nvgl "vendor:nanovg/gl"
Color :: struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
}
ModuleItem :: struct {
    text:    string,
    fg:      Color,
    bg:      Color,
    tooltip: string,
    menu:    map[string]string,
}
Module :: struct {
    pid: os.Pid, 
    exec: string,
    clickable: bool,
    current_items: []ModuleItem,
}
Monitor :: struct {
    output:          ^wl.wl_output,
    name:            string,
    egl_surface:     egl.Surface,
    egl_window:      ^wl.egl_window,
    surface:         ^wl.wl_surface,
    layer_surface:   ^wl.zwlr_layer_surface_v1,
    w:               int,
    h:               int,
    scale:           int,
    modules:         []Module,
    refresh_surface: bool,
    nanovg_ctx:      ^nanovg.Context,
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
}

get_or_create_monitor_for_output :: proc(st: ^State, output: ^wl.wl_output) -> ^Monitor {
    context.user_ptr = output
    i, found := slice.linear_search_proc(st.monitors[:], proc(x: ^Monitor) -> bool { return context.user_ptr == x.output })
    if found do return st.monitors[i]
    mon := new(Monitor)
    mon.output = output
    append(&st.monitors, mon)
    return mon
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
    monitor.w = int(width)
    monitor.h = int(height)
}
output_done  :: proc "c" (data: rawptr, wl_output: ^wl.wl_output) {
    st := transmute(^State)data
    context = st.ctx
    monitor := get_or_create_monitor_for_output(st, wl_output)
    monitor.refresh_surface = true
}
output_scale :: proc "c" (data: rawptr, wl_output: ^wl.wl_output, factor: c.int32_t) {
    st := transmute(^State)data
    context = st.ctx
    monitor := get_or_create_monitor_for_output(st, wl_output)
    monitor.scale = int(factor)
}
output_name  :: proc "c" (data: rawptr, wl_output: ^wl.wl_output, name: cstring) {
    st := transmute(^State)data
    context = st.ctx
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
pointer_listener: wl.wl_pointer_listener = {
    enter = proc "c" (
        data: rawptr,
        wl_pointer: ^wl.wl_pointer,
        serial: c.uint32_t,
        surface: ^wl.wl_surface,
        surface_x: wl.wl_fixed_t,
        surface_y: wl.wl_fixed_t,
    ) {},
    leave = proc "c" (
        data: rawptr,
        wl_pointer: ^wl.wl_pointer,
        serial: c.uint32_t,
        surface: ^wl.wl_surface,
    ) {},
    motion = proc "c" (
        data: rawptr,
        wl_pointer: ^wl.wl_pointer,
        time: c.uint32_t,
        surface_x: wl.wl_fixed_t,
        surface_y: wl.wl_fixed_t,
    ) {
        state: ^State = cast(^State)data
        context = state.ctx
    },
    button = proc "c" (
        data: rawptr,
        wl_pointer: ^wl.wl_pointer,
        serial: c.uint32_t,
        time: c.uint32_t,
        button: c.uint32_t,
        state: c.uint32_t,
    ) {},
    axis = proc "c" (
        data: rawptr,
        wl_pointer: ^wl.wl_pointer,
        time: c.uint32_t,
        axis: c.uint32_t,
        value: wl.wl_fixed_t,
    ) {},
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

get_buffer :: proc(state: ^State, width: c.int32_t, height: c.int32_t) -> ^wl.wl_buffer {
    stride := width * 4
    shm_pool_size := height * stride

    fd := cast(posix.FD)utils.allocate_shm_file(cast(uint)shm_pool_size)
    if fd < 0 {
        fmt.println("Errror")
        return nil
    }
    pool := wl.wl_shm_create_pool(state.shm, cast(c.int32_t)fd, shm_pool_size)

    pool_data := posix.mmap(
        nil,
        cast(uint)shm_pool_size,
        {posix.Prot_Flag_Bits.READ, posix.Prot_Flag_Bits.WRITE},
        {posix.Map_Flag_Bits.SHARED},
        fd,
        0,
    )
    buffer := wl.wl_shm_pool_create_buffer(pool, 0, width, height, stride, 0)

    wl.wl_shm_pool_destroy(pool)
    posix.close(fd)


    //posix.munmap(pool_data, cast(uint)shm_pool_size)
    pixels := cast([^]pixel)pool_data
    for i in 1 ..= shm_pool_size / 4 {
        pixels[i].a = 255
        pixels[i].r = 0x9a
        pixels[i].g = 0xce
        pixels[i].b = 0xeb
    }

    wl.wl_buffer_add_listener(buffer, &buffer_listener, nil)

    return buffer
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
monitor_refresh_surface :: proc(state: ^State, monitor: ^Monitor) {
    monitor.refresh_surface = false
    if monitor.surface != nil do wl.wl_surface_destroy(monitor.surface) 
    if monitor.egl_surface != nil {
        egl.DestroySurface(state.rctx.display, monitor.egl_surface) 
        wl.egl_window_destroy(monitor.egl_window)
    }
    monitor.surface = wl.wl_compositor_create_surface(state.compositor)

    monitor.layer_surface = wl.zwlr_layer_shell_v1_get_layer_surface(state.layer_shell, monitor.surface, monitor.output, wl.ZWLR_LAYER_SHELL_V1_LAYER_TOP, "wb")
    wl.zwlr_layer_surface_v1_set_size(monitor.layer_surface, u32(monitor.w), HEIGHT)
    wl.zwlr_layer_surface_v1_set_anchor(monitor.layer_surface, wl.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP)

    wl.zwlr_layer_surface_v1_set_keyboard_interactivity(monitor.layer_surface, wl.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND)
    wl.zwlr_layer_surface_v1_add_listener(monitor.layer_surface, &layer_listener, nil)

    wl.wl_surface_commit(monitor.surface)
    wl.display_roundtrip(state.display)
    monitor.egl_window = wl.egl_window_create(monitor.surface, i32(monitor.w), HEIGHT)
    fmt.println(monitor.egl_window == nil)
    monitor.egl_surface = egl.CreateWindowSurface(
        state.rctx.display,
        state.rctx.config,
        egl.NativeWindowType(monitor.egl_window),
        nil,
    )
    if monitor.egl_surface == egl.NO_SURFACE {
        fmt.println("Error creating window surface")
        os.exit(1)
    }
}
HEIGHT :: 25
main :: proc() {
    state: State = {}
    state.ctx = context
    cfg, err := load_config()
    if err != nil {
        fmt.eprintln("ERROR:", err)
        os.exit(1)
    }
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

    state.rctx = render.init_egl(display)
    gl.load_up_to(int(4), 5, egl.gl_set_proc_address)
    for monitor in state.monitors {
        monitor_refresh_surface(&state, monitor)
    }
    wl.display_roundtrip(display)


    for monitor in state.monitors {
        if (!egl.MakeCurrent(state.rctx.display, monitor.egl_surface, monitor.egl_surface, state.rctx.ctx)) {
            fmt.println("Error making current!")
            return
        }
        monitor.nanovg_ctx = nvgl.Create({.DEBUG, .ANTI_ALIAS, .STENCIL_STROKES})
        nanovg.CreateFont(monitor.nanovg_ctx, "sans", "/usr/share/fonts/TTF/NotoSansMNerdFont-Regular.ttf")
    }
    wl.display_roundtrip(display)

    for {
        for monitor in state.monitors {
            if (!egl.MakeCurrent(state.rctx.display, monitor.egl_surface, monitor.egl_surface, state.rctx.ctx)) {
                fmt.println("Error making current!")
                return
            }
            {
                ctx := monitor.nanovg_ctx
                nanovg.BeginFrame(ctx, f32(monitor.w), f32(HEIGHT), 1)
                defer nanovg.EndFrame(ctx)
                nanovg.FillColor(ctx, nanovg.RGBA(0, 0, 0, 0xFF))
                nanovg.Fill(ctx)
                nanovg.FontSize(ctx, 17.5)
                nanovg.FontFaceId(ctx, 0)
                nanovg.FillColor(ctx, nanovg.RGBA(0xc7, 0xab, 0x7a,255))
                nanovg.Text(ctx, 5, 18,  "1: Hello, world" )
            }


            egl.SwapBuffers(state.rctx.display, monitor.egl_surface)
            wl.wl_surface_damage_buffer(monitor.surface, 0, 0, 10, 10)
            wl.wl_surface_commit(monitor.surface)
            wl.display_roundtrip(display)
            wl.display_dispatch(display)
        }
    }
}
