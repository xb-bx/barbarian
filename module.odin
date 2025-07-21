package barbarian
import "core:sys/posix"
import "core:container/queue"
import "core:encoding/json"
import "core:strings"
import "core:strconv"
import "core:slice"
import "core:bufio"
import "core:io"
import "core:os"
import "core:fmt"
import "vendor:nanovg"
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
ModuleMenuItem :: struct {
    key: string,
    value: string,
}
ModuleMenu :: struct {
    items:   []ModuleMenuItem,
    open_on: MouseButton,
}
ModuleInput :: struct {
    items:   Maybe([]ModuleItem),
    menu:    Maybe(ModuleMenu),
    tooltip: Maybe(string),
}
ClickEvent :: struct {
    button: MouseButton,
    item: int,
}
MenuEvent :: struct {
    key: string,
}
ScrollEvent :: struct {
    dir: int,
}
ModuleEventType :: enum {
    Click,
    Menu,
    Scroll,
}
ModuleEvent :: struct {
    type:   ModuleEventType,
    click:  Maybe(ClickEvent)  `json:"event,omitempty"`,
    menu:   Maybe(MenuEvent)   `json:"event,omitempty"`,
    scroll: Maybe(ScrollEvent) `json:"event,omitempty"`,
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
    min_width:       f32,
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
    posix.fcntl(module.pipe_in[1], .SETFL, posix.fcntl(module.pipe_in[1], .GETFL, 0) | posix.O_NONBLOCK)
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
delete_menu :: proc(menu: ModuleMenu) {
    for item in menu.items {
        delete(item.key)
        delete(item.value)
    }
    delete(menu.items)
}
send_event :: proc(module: ^Module, event: ModuleEvent) {
    b : strings.Builder = {}
    defer strings.builder_destroy(&b)
    strings.builder_init(&b)
    opt := json.Marshal_Options {pretty = false, spec = .JSON, use_enum_names = true, }
    err := json.marshal_to_builder(&b, event, &opt)
    if err != nil { fmt.eprintln(err); panic("err") }
    strings.write_rune(&b, '\n')

    res := posix.write(module.pipe_in[1], slice.as_ptr(b.buf[:]), len(b.buf))
    if res == -1 {
        fmt.eprintln("WARN: Could not send event to module", posix.errno())
    }
}
calculate_width :: proc(module: ^Module, ctx: ^nanovg.Context) -> f32 {
    if module.current_input.items == nil do return 0
    sum := f32(0)
    items := module.current_input.items.([]ModuleItem)
    for item in items {
        bounds := [4]f32 {}
        nanovg.TextAlign(ctx, .CENTER, .BASELINE)
        adv := nanovg.TextBounds(ctx, 0, 0, item.text, &bounds)
        text_width := adv
        width := text_width + PAD*2
        sum += width
    }
    return max(sum, module.min_width)
}
module_render :: proc(mod: ^Module, state: ^State, ctx: ^nanovg.Context, x: f32) -> f32 {
    if mod.current_input.items == nil do return 0
    x := x
    for &item in mod.current_input.items.([]ModuleItem) {
        bounds := [4]f32 {}
        nanovg.TextAlign(ctx, .LEFT, .BASELINE)
        adv := nanovg.TextBounds(ctx, 0, state.height, item.text, &bounds)
        text_width := adv
        text_height := bounds[3]-bounds[1]
        width := text_width + PAD*2

        nanovg.FillColor(ctx, nanovg.RGBA(item.bgColor.r, item.bgColor.g, item.bgColor.b,item.bgColor.a))
        nanovg.BeginPath(ctx)
        nanovg.Rect(ctx, x, 0, width, state.height)
        nanovg.Fill(ctx)

        nanovg.FillColor(ctx, nanovg.RGBA(item.fgColor.r, item.fgColor.g, item.fgColor.b,item.fgColor.a))
        nanovg.Text(ctx, x + PAD, state.height + (state.height-text_height)/2 - bounds[1], item.text)
        item.pos = x
        item.width = width
        x += width
    }
    return max(x, mod.min_width)
}
process_input :: proc(module: ^Module, state: ^State) {
    line, err := bufio.reader_read_string(&module.rd, '\n')
    if err != nil {
        fmt.eprintln("ERROR: while reading module input", err) 
    }
    defer delete(line)
    input: ModuleInput = {}
    jerr := json.unmarshal_string(line, &input, .JSON)
    if jerr != nil {
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
                item.fgColor = state.fg
            } 
            item.bgColor, ok = hex_to_color(item.bg)
            if !ok {
                fmt.eprintln("WARN: received invalid color", item.bg)
                item.bgColor = state.bg
            } 
        } 
        if module.current_input.items != nil do delete_items(module.current_input.items.([]ModuleItem))
        module.current_input.items = items
        module.redraw = true
    } 
    if input.menu != nil {
        menu := input.menu.(ModuleMenu)
        fmt.println(menu)
        if module.current_input.menu != nil do delete_menu(module.current_input.menu.(ModuleMenu))
        module.current_input.menu = menu
    }
    if input.tooltip != nil {
        if module.current_input.tooltip != nil do delete(module.current_input.tooltip.(string))
        module.current_input.tooltip = input.tooltip
    }
} 
