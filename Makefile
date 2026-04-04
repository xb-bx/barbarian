./barbarian: *.odin ./wayland-odin/wayland/cursor_shape_v1.odin ./wayland-odin/wayland/tablet_v2.odin
	odin build . -debug -error-pos-style:unix -out:$@ -linker:lld
debug-barbarian: ./barbarian
	gdb --args ./barbarian --config-path ./test_config.json5
./wayland-odin/scanner: ./wayland-odin/scanner.odin
	odin build ./wayland-odin/scanner.odin -file -out:$@
./wayland-odin/wayland/cursor_shape_v1.odin: ./cursor-shape-v1.xml ./wayland-odin/scanner
	./wayland-odin/scanner -i ./cursor-shape-v1.xml -o $@
./wayland-odin/wayland/tablet_v2.odin: ./tablet-v2.xml ./wayland-odin/scanner
	./wayland-odin/scanner -i ./tablet-v2.xml -o $@

DESTDIR ?= /
.PHONY: install
.PHONY: release
release: ./wayland-odin/wayland/cursor_shape_v1.odin ./wayland-odin/wayland/tablet_v2.odin
	odin build . -o:speed -out:./barbarian
install: 
	mkdir -p "$(DESTDIR)usr/bin"
	install -Dm755 barbarian "${DESTDIR}usr/bin/barbarian"
