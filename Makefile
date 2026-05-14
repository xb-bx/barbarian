INTERFACES=$(shell find interfaces -type f)
GENERATED=$(shell find interfaces -type f | sed 's,.*/,,g' | sed 's/.xml/.odin/' | sed 's,^,wayland-odin/wayland/,')
./barbarian: *.odin $(GENERATED)
	odin build . -debug -error-pos-style:unix -vet -vet-packages:barbarian -out:$@ -linker:lld
debug-barbarian: ./barbarian
	gdb --args ./barbarian --config-path ./test_config.json5
./wayland-odin/scanner: ./wayland-odin/scanner.odin
	odin build ./wayland-odin/scanner.odin -file -out:$@
./wayland-odin/wayland/%.odin: ./interfaces/%.xml ./wayland-odin/scanner
	./wayland-odin/scanner -i $< -o $@

DESTDIR ?= /
.PHONY: install
.PHONY: release
release: $(GENERATED)
	odin build . -o:speed -out:./barbarian
install: 
	mkdir -p "$(DESTDIR)usr/bin"
	install -Dm755 barbarian "${DESTDIR}usr/bin/barbarian"
