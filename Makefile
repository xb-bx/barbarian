./barbarian: *.odin 
	odin build . -debug -error-pos-style:unix -out:$@ -linker:lld
debug-barbarian: ./barbarian
	gdb --args ./barbarian --config-path ./test_config.json5

DESTDIR ?= /
.PHONY: install
install: 
	odin build . -o:speed -out:./barbarian
	mkdir -p "$(DESTDIR)usr/bin"
	install -Dm755 barbarian "${DESTDIR}usr/bin/barbarian"
