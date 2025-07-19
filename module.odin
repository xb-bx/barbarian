package barbarian
import "core:sys/posix"
import "core:encoding/json"
import "core:strings"
import "core:strconv"
import "core:slice"
import "core:bufio"
import "core:io"
import "core:os"
import "core:fmt"
Color :: struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
}
ModuleItem :: struct {
    text:    string,
    fgColor: Color,
    bgColor: Color,
    fg:      string, 
    bg:      string, 
    pos:     f32,
    width:   f32,
}
ModuleInput :: struct {
    items:   Maybe([]ModuleItem),
    menu:    Maybe(map[string]string),
    tooltip: Maybe(string),
}

Module :: struct {
    pid:             posix.pid_t, 
    exec:            []string,
    clickable:       bool,
    current_input:   ModuleInput,
    pipe_in:         [2]posix.FD,
    pipe_out:        [2]posix.FD,
    rd:              bufio.Reader,
    redraw:          bool,
    pollfd_index:    int,
}
fork :: proc() -> (posix.pid_t, posix.Errno) {
    res := posix.fork()
    if res == -1 do return -1, posix.get_errno()
    return res, nil
}
pipe :: proc(fdes: ^[2]posix.FD) -> posix.Errno {
    if posix.pipe(fdes) == .FAIL do return posix.get_errno()
    return nil
}
run_module :: proc(module: ^Module) -> posix.Errno {
    pipe(&module.pipe_in) or_return
    pipe(&module.pipe_out) or_return
    fmt.println(1)
    pid := fork() or_return
    if pid == 0 {
        posix.close(module.pipe_in[1])
        posix.close(module.pipe_out[0])
        posix.dup2(module.pipe_in[0], posix.FD(0))
        posix.dup2(module.pipe_out[1], posix.FD(1))
        cstrings := make([]cstring, len(module.exec))
        for str,i in module.exec do cstrings[i] = strings.clone_to_cstring(str)
        posix.execvp(cstrings[0], slice.as_ptr(cstrings))
        posix.exit(1)
    } else {
        posix.close(module.pipe_in[0])
        posix.close(module.pipe_out[1])
        module.pid = pid
    }
    
    bufio.reader_init(&module.rd, os.stream_from_handle(os.Handle(module.pipe_out[0])))
    return nil
}
EMPTY_ITEMS := []string { "THERE IS NOTHING HERE" }
hex_to_color :: proc(hex: string) -> (Color, bool) {
    if len(hex) < 8 do return {}, false
    res := Color {}
    hex := hex
    bytes := transmute([^]byte)&res
    for i in 0..<4 {
        num, ok := strconv.parse_uint(hex[:2], 16)
        if !ok do return {}, false
        bytes[i] = u8(num)
        hex = hex[2:]
    }
    return res, true
}
delete_items :: proc(items: []ModuleItem) {
    for item in items {
        delete(item.fg)
        delete(item.bg)
        delete(item.text)
    }
    delete(items)
}
delete_menu :: proc(menu: map[string]string) {
    for k,v in menu {
        delete(k)
        delete(v)
    }
    delete(menu)
}
process_input :: proc(module: ^Module) {
    line, err := bufio.reader_read_string(&module.rd, '\n')
    fmt.println("READ") 
    if err != nil {
        fmt.eprintln("ERROR: while reading module input", err) 
    }
    defer delete(line)
    input: ModuleInput = {}
    jerr := json.unmarshal_string(line, &input, .JSON5)
    if jerr != nil {
        fmt.println(jerr)
        items := make([]ModuleItem, 1)
        if module.current_input.items != nil do delete_items(module.current_input.items.([]ModuleItem))
        module.current_input.items = items
        items[0].text = strings.clone(strings.trim(line, "\n\r"))
        items[0].bgColor = Color { 0, 0, 0, 0 }
        items[0].fgColor = Color { 255, 255, 255, 255 }
        module.redraw = true
        return
    }
    if input.items != nil {
        items := input.items.([]ModuleItem)
        for &item in items {
            ok := false
            item.fgColor, ok = hex_to_color(item.fg)
            if !ok {
                fmt.eprintln("WARN: received invalid color", item.fg)
                item.fgColor = Color { 255, 255, 255, 255 }
            } 
            item.bgColor, ok = hex_to_color(item.bg)
            if !ok {
                fmt.eprintln("WARN: received invalid color", item.bg)
                item.bgColor = Color { 0, 0, 0, 255 }
            } 
        } 
        if module.current_input.items != nil do delete_items(module.current_input.items.([]ModuleItem))
        module.current_input.items = items
        module.redraw = true
    } 
    if input.menu != nil {
        menu := input.menu.(map[string]string)
        if module.current_input.menu != nil do delete_menu(module.current_input.menu.(map[string]string))
        module.current_input.menu = menu
    }
    if input.tooltip != nil {
        if module.current_input.tooltip != nil do delete(module.current_input.tooltip.(string))
        module.current_input.tooltip = input.tooltip
    }
} 
