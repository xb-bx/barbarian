package barbarian
import "core:log"
import "vendor:egl"
import wl "wayland-odin/wayland"
import render "wayland-odin/render"
foreign import foo "system:EGL"


Error :: enum i32 {
    SUCCESS             = 0x3000,
    NOT_INITIALIZED     = 0x3001,
    BAD_ACCESS          = 0x3002,
    BAD_ALLOC           = 0x3003,
    BAD_ATTRIBUTE       = 0x3004,
    BAD_CONFIG          = 0x3005,
    BAD_CONTEXT         = 0x3006,
    BAD_CURRENT_SURFACE = 0x3007,
    BAD_DISPLAY         = 0x3008,
    BAD_MATCH           = 0x3009,
    BAD_NATIVE_PIXMAP   = 0x300A,
    BAD_NATIVE_WINDOW   = 0x300B,
    BAD_PARAMETER       = 0x300C,
    BAD_SURFACE         = 0x300D,
    CONTEXT_LOST        = 0x300E,
}
@(default_calling_convention = "c", link_prefix = "egl")
foreign foo {
    GetError :: proc() -> Error ---
    GetConfigs :: proc(display: egl.Display, config: ^egl.Config, config_size: i32, num_config: ^i32) -> egl.Boolean ---
    ChooseConfig :: proc(display: egl.Display, attrib_list: ^i32, configs: ^egl.Config, config_size: i32, num_config: ^i32) -> egl.Boolean ---
}
init_egl :: proc(display: ^wl.wl_display) -> render.RenderContext {
    major, minor, n: i32
    count: i32 = 0
    egl_conf: egl.Config
    config_attribs: []i32 = {
        egl.SURFACE_TYPE,
        egl.WINDOW_BIT,
        egl.RED_SIZE,
        8,
        egl.GREEN_SIZE,
        8,
        egl.BLUE_SIZE,
        8,
        egl.ALPHA_SIZE,
        8,
        egl.RENDERABLE_TYPE,
        egl.OPENGL_BIT,
        egl.NONE,
    }
    context_attribs: []i32 = {egl.CONTEXT_CLIENT_VERSION, 2, egl.NONE}
    egl_display := egl.GetDisplay(egl.NativeDisplayType(display))

    GetError() // clear error code
    if (egl_display == egl.NO_DISPLAY) {
        log.error("Can't create egl display")
    } else {
        log.debug("Created egl display")
    }
    if (!egl.Initialize(egl_display, &major, &minor)) {
        log.errorf("Can't initialise egl display, error code: 0x%x", GetError())
    }
    log.debugf("EGL major: %d, minor %d", major, minor)
    if (!GetConfigs(egl_display, nil, 0, &count)) {
        log.errorf("Can't get EGL configs, error code: 0x%x", GetError())
    }
    log.debugf("EGL has %d configs", count)

    res := ChooseConfig(egl_display, raw_data(config_attribs), &egl_conf, 1, &n)
    if res == egl.FALSE {
        log.errorf("Error choosing config, error code: 0x%x", GetError())
    }
    log.debugf("EGL chose %d configs", n)

    egl.BindAPI(egl.OPENGL_API)

    egl_context := egl.CreateContext(
        egl_display,
        egl_conf,
        egl.NO_CONTEXT,
        raw_data(context_attribs),
    )
    log.debugf("EGL context: %v", egl_context)

    return render.RenderContext{ctx = egl_context, display = egl_display, config = egl_conf}
}
