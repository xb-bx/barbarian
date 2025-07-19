./barbarian: *.odin 
	odin build . -debug -error-pos-style:unix -out:$@ -linker:lld
