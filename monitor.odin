#+feature using-stmt
package barbarian
import "core:strings"
import "core:slice"
import "core:time"
import "core:fmt"
import "core:c"
import wl "wayland-odin/wayland"

import gl "vendor:OpenGL"
import "vendor:egl"
import "vendor:nanovg"
import nvgl "vendor:nanovg/gl"
MonitorIterator :: struct {
    monitor: ^Monitor,
    idx:     int,
    inner:   int,
}
Monitor :: struct {
    mouse_handler:   MouseHandler,
    wl_name:         c.uint32_t,
    output:          ^wl.wl_output,
    name:            string,
    left:            []Module,
    right:           []Module,
    surface:         Surface,
    geom_changed:    bool,
}
monitor_iter :: proc(using iter: ^MonitorIterator) -> (^Module, bool) {
    mods: []Module = {}
    for idx < 2 {
        switch idx {
            case 0:
                mods = monitor.left
            case 1:
                mods = monitor.right
        }
        if inner >= len(mods) {
            idx += 1
            inner = 0
            continue
        }
        inner += 1
        return &mods[inner - 1], true
    }
    return nil, false
}
monitor_get_mod_at :: proc(mon: ^Monitor, pos_x: f32, pos_y: f32) -> (^Module, int) {
    mod_iter := MonitorIterator { monitor = mon }  
    res_mod: ^Module = nil
    index := -1
    for mod in monitor_iter(&mod_iter) {
        if mod.current_input.items == nil do continue
        items := mod.current_input.items.([]ModuleItem)
        for item, i in items {
            if pos_x >= item.pos && pos_x <= item.pos + item.width {
                index = i
                res_mod = mod
                break
            }
        }
        if res_mod != nil do break
    }
    return res_mod, index
}
monitor_mouse_motion :: proc(data: rawptr, state: ^State, pos_x: f32, pos_y: f32) {
    mon := cast(^Monitor)data
    res_mod, _ := monitor_get_mod_at(mon, pos_x, pos_y)
    if res_mod != nil {
        if state.tooltip != nil {
            if state.tooltip.module == res_mod {
                if !state.tooltip.displayed {
                    state.tooltip.time = time.now()
                }
                return
            }
            tooltip_destroy(state.tooltip, state)
            state.tooltip = nil
        } else if res_mod.current_input.tooltip != nil {
            state.tooltip = new(Tooltip)
            tooltip_init(state.tooltip, res_mod, mon, mon.surface.nvg_ctx) 
        }
    } else if state.tooltip != nil {
        tooltip_destroy(state.tooltip, state)
        state.tooltip = nil
    }

}
monitor_mouse_scroll :: proc(data: rawptr, state: ^State, dir: int) {
    mon := cast(^Monitor)data
    res_mod, item_index := monitor_get_mod_at(mon, state.mouse.pos_x, state.mouse.pos_y)
    if res_mod != nil {
        send_event(res_mod, ModuleEvent { type = .Scroll, scroll = ScrollEvent { dir = dir }})
    }
}
restart_items := []ModuleMenuItem { { "stop", "Stop", }, { "restart", "Restart" }, }
monitor_mouse_click :: proc(data: rawptr, state: ^State, btn: MouseButton, serial: u32) {
    mon := cast(^Monitor)data
    menu_close(state)
    mod_iter := MonitorIterator { monitor = mon }  
    res_mod: ^Module = nil
    item_index := -1
    for mod in monitor_iter(&mod_iter) {
        if mod.current_input.items == nil do continue
        items := mod.current_input.items.([]ModuleItem)
        for item, i in items {
            if state.mouse.pos_x >= item.pos && state.mouse.pos_x <= item.pos + item.width {
                item_index = i 
                res_mod = mod
                break
            }
        }
        if res_mod != nil do break
    }
    if res_mod != nil {
        if state.ctrl_pressed && btn == .Right {
            state.menu = new(Menu)
            menu_init(state.menu, state, mon, { items = restart_items }, proc(data: rawptr, index: int) { 
                mod := cast(^Module)data
                if index == 0 {
                    module_stop(mod)
                } else if index == 1 {
                    module_stop(mod)
                    mod.stopped = false
                    module_run(mod)
                }
            }, res_mod, mon.surface.nvg_ctx)
        } else if res_mod.current_input.menu != nil && res_mod.current_input.menu.(ModuleMenu).open_on == btn {
            state.menu = new(Menu)
            menu := res_mod.current_input.menu.(ModuleMenu)
            menu_init(state.menu, state, mon, menu, proc(data: rawptr, index: int) {
                mod := cast(^Module)data
                item := mod.current_input.menu.(ModuleMenu).items[index]   
                send_event(mod, { type = .Menu, menu = MenuEvent { key = item.key } })
            }, res_mod, mon.surface.nvg_ctx)
            wl.xdg_popup_grab(state.menu.surface.xdg_popup, state.seat, serial)
        } else {
            if res_mod.clickable {
                send_event(res_mod, { type = .Click, click = ClickEvent { button = btn, item = item_index } })
            }
        }
    }
}
get_monitor_by_name :: proc(st: ^State, name: string) -> ^Monitor {
    for mon in st.monitors do if mon.name == name do return mon
    return nil
}
get_monitor_by_surface :: proc(st: ^State, surface: ^wl.wl_surface) -> ^Monitor {
    context.user_ptr = surface
    i, found := slice.linear_search_proc(st.monitors[:], proc(x: ^Monitor) -> bool { return context.user_ptr == x.surface.wl_surface })
    if found do return st.monitors[i]
    return nil
}
get_or_create_monitor_for_output :: proc(st: ^State, output: ^wl.wl_output) -> ^Monitor {
    context.user_ptr = output
    i, found := slice.linear_search_proc(st.monitors[:], proc(x: ^Monitor) -> bool { return context.user_ptr == x.output })
    if found do return st.monitors[i]
    mon := new(Monitor)
    mon.mouse_handler = {
        data = mon,
        motion = monitor_mouse_motion,
        click = monitor_mouse_click,
        scroll = monitor_mouse_scroll,
    }
    mon.output = output
    append(&st.monitors, mon)
    return mon
}
monitor_destroy :: proc(mon: ^Monitor) {
    for &mod in mon.left {
        if !mod.stopped do module_stop(&mod) 
        module_delete(&mod)
    }
    for &mod in mon.right {
        if !mod.stopped do module_stop(&mod) 
        module_delete(&mod)
    }
    delete(mon.left)
    delete(mon.right)
    if mon.surface.nvg_ctx != nil do nvgl.Destroy(mon.surface.nvg_ctx)
    if mon.surface.wl_surface != nil do surface_destroy(&mon.surface)
    wl.wl_output_release(mon.output)
}
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
        err := module_run(&mod)
        if err != nil do fmt.eprintln("ERROR: Failed to run module", mod.exec)
    }
}
monitor_reload :: proc(state: ^State, cfg: ^Config, monitor: ^Monitor) {
    monitor.surface.redraw = true
    monitor.geom_changed = false
    if monitor.surface.nvg_ctx != nil do nvgl.Destroy(monitor.surface.nvg_ctx)

    if monitor.surface.wl_surface != nil do surface_destroy(&monitor.surface)
    if monitor.left == nil && monitor.right == nil {
        for name, out in cfg.outputs {
            if name == monitor.name {
                init_modules(&monitor.left, cfg, out.modules_left)
                init_modules(&monitor.right, cfg, out.modules_right)
                break
            }
        }
    }
    surface_init(&monitor.surface, monitor.output, state, monitor.surface.w, monitor.surface.h, LayerSurface{})

    if (!egl.MakeCurrent(state.rctx.display, monitor.surface.egl_surface, monitor.surface.egl_surface, state.rctx.ctx)) {
        fmt.println("Error making current!")
        return
    }
    monitor.surface.nvg_ctx = nvgl.Create({.DEBUG, .ANTI_ALIAS})
    nanovg.CreateFontMem(monitor.surface.nvg_ctx, "sans", state.font, false)
    monitor.surface.redraw = true
    monitor.surface.swap = true
}
