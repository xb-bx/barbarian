package barbarian
import "core:strings"
import "core:slice"
import "core:time"
import "core:fmt"
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
    output:          ^wl.wl_output,
    name:            string,
    left:            []Module,
    right:           []Module,
    surface:         Surface,
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
        if res_mod.current_input.menu != nil && res_mod.current_input.menu.(ModuleMenu).open_on == btn {
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
