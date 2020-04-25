.PHONY: all clean time regen_input

# Number of text segments in the generated input text, each of which
# will have some size variation. 100,000 produces a file of a few
# megabytes.
INPUT_SIZE ?= 100000

# Type of optimization to apply to the programs under test
# Supply one of the valid suffixes to swiftc's `-O` flag:
# `none`, `unchecked`, `size`, or the empty string
# Defaults to standard optimization, equivalent to the empty string
OPTIMIZATION ?= ""

optimization_flag := -O$(OPTIMIZATION)
build_dir := ./build
	
#--- Targets to be run as "commands"

all: input.txt $(build_dir)/raw $(build_dir)/useCharacter

time: input.txt $(build_dir)/raw $(build_dir)/useCharacter
	time $(build_dir)/raw >/dev/null
	time $(build_dir)/useCharacter >/dev/null

# By default, running `all` will preserve the input file;
# it can be explicitly recreated with this target.
regen_input: $(build_dir)/generateInput
	$(build_dir)/generateInput $(INPUT_SIZE) > input.txt

clean:
	-rm -rf $(build_dir)
	-rm -f input.txt

#--- Internal targets

input.txt: $(build_dir)/generateInput
	$(build_dir)/generateInput $(INPUT_SIZE) > input.txt

$(build_dir)/raw: raw.swift | build
	swiftc $(optimization_flag) raw.swift -o $(build_dir)/raw
	
$(build_dir)/useCharacter: useCharacter.swift | $(build_dir)
	swiftc $(optimization_flag) useCharacter.swift -o $(build_dir)/useCharacter

$(build_dir)/generateInput: generateInput.swift | $(build_dir)
	swiftc -O generateInput.swift -o $(build_dir)/generateInput

$(build_dir):
	mkdir -p $(build_dir)
