./barbarian: *.odin 
	odin build . -debug -error-pos-style:unix -out:$@ -linker:lld
debug-barbarian: ./barbarian
	gdb --args ./barbarian --config-path ./test_config.json5

DESTDIR ?= /
.PHONY: install
.PHONY: release
release: 
	odin build . -o:speed -out:./barbarian
install: 
	mkdir -p "$(DESTDIR)usr/bin"
	install -Dm755 barbarian "${DESTDIR}usr/bin/barbarian"
