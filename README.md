# BARbarian - simple wayland bar
### Demo 
![demo.png](https://github.com/xb-bx/barbarian/blob/master/demo.png?raw=true)
### Configuration
The bar looks for $XDG_CONFIG_HOME/barbarian/config.json5 or $HOME/.config/barbarian/config.json5
[example config](https://github.com/xb-bx/barbarian/tree/master/config.json5)

### Useful
To restart or stop a module right-click it while holding CTRL

### Custom modules
The bar communicates with modules via stdio
A module must write either plain text or json to stdout

Example module output:
```json
{
    "items": [
        {"text": "Hello, world", "fg": "ffffffff", "bg": "000000ff"}
    ],
    "tooltip": "Some tooltip",
    "menu": {
        "open_on": "Left",   
        "items": [
            {"key": "Hello", "value": "World"}
        ]
    }
}
```
> [!NOTE]
> The json must not contain new lines

The module receives events(click, scroll, menu-item selected) via stdin

Example module input:
```json
{
    "type": "Click", // Can be "Scroll" or "Menu",
    "event": {
        "button": "Left", // Can be "Right" or "Middle"
        "item": 0, // Clicked item index
    }
}
```
```json
{
    "type": "Scroll", 
    "event": {
        "dir": -1,
    }
}
```
```json
{
    "type": "Menu", 
    "event": {
        "key": "Hello",
    }
}
```
Look for examples in [./example-modules](https://github.com/xb-bx/barbarian/tree/master/example-modules)
## TODO:
- [x] Test multiple monitors
- [ ] Scaling


# Installation
## Arch-based distros
```sh
git clone https://github.com/xb-bx/barbarian
cd barbarian
makepkg -si
```

## Other
```sh
git clone https://github.com/xb-bx/barbarian --recursive
sudo make install
```


