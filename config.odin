package barbarian
import "core:os"
import "core:encoding/json"

OutputConfig :: struct {
    modules_left:   []string, 
    modules_center: []string,
    modules_right:  []string,
}
ModuleConfig :: struct {
    exec:      []string,
    clickable: bool,
}
Config :: struct {
    outputs:    map[string]OutputConfig,
    modules:    map[string]ModuleConfig,
    background: string,
}
ConfigError :: union #shared_nil {
    os.Error,
    json.Unmarshal_Error,
}
load_config :: proc() -> (cfg: ^Config, err: ConfigError) {
    file := os.read_entire_file_from_filename_or_err("./config.json5") or_return
    defer delete(file)
    cfg = new(Config)
    json.unmarshal(file, cfg, json.Specification.JSON5) or_return
    return cfg, nil
}
