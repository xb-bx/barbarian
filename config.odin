package barbarian
import "core:os"
import "core:path/filepath"
import "core:encoding/json"

OutputConfig :: struct {
    modules_left:   []string, 
    modules_right:  []string,
}
ModuleConfig :: struct {
    exec:      []string,
    clickable: bool,
    min_width: f32,
}
Config :: struct {
    outputs:    map[string]OutputConfig,
    modules:    map[string]ModuleConfig,
    background: string,
    foreground: string,
    tooltip_background: string,
    tooltip_foreground: string,
    menu_background: string,
    menu_foreground: string,
    font:       string,
    font_size:  f32,
    height:     f32,
}
ConfigError :: union #shared_nil {
    os.Error,
    json.Unmarshal_Error,
}
load_config :: proc(config_path: string) -> (cfg: ^Config, err: ConfigError) {
    config_path := config_path
    if config_path == "" {
        config_path = os.get_env("XDG_CONFIG_HOME")
        if config_path == "" {
            arr := [4]string{os.get_env("HOME"), ".config", "barbarian", "config.json5"}
            config_path = filepath.join(arr[:])
        } else {
            arr := [3]string{config_path, "barbarian", "config.json5"}
            config_path = filepath.join(arr[:])
        }
    } 

    file := os.read_entire_file_from_filename_or_err(config_path) or_return
    defer delete(file)
    cfg = new(Config)
    json.unmarshal(file, cfg, json.Specification.JSON5) or_return
    return cfg, nil
}
