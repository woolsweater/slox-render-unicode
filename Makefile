.PHONY: all clean time diff regen_input

# Number of text segments in the generated input text, each of which
# will have some size variation. 100,000 produces a file of a few
# megabytes.
INPUT_SIZE ?= 100000

# Type of optimization to apply to the programs under test
# Supply one of the valid suffixes to swiftc's `-O` flag:
# `none`, `unchecked`, `size`, or the empty string
# Defaults to standard optimization, equivalent to the empty string
OPTIMIZATION ?= ""
C_OPTIMIZATION ?= ""

optimization_flag := -O$(OPTIMIZATION)
c_optimization_flag := -O$(C_OPTIMIZATION)
build_dir := ./build
output_dir := ./output
	
#--- Targets to be run as "commands"

all: input.txt $(build_dir)/raw $(build_dir)/useCharacter $(build_dir)/c_impl

time: input.txt $(build_dir)/raw $(build_dir)/useCharacter $(build_dir)/c_impl
	time $(build_dir)/raw >/dev/null
	time $(build_dir)/useCharacter >/dev/null
	time $(build_dir)/c_impl >/dev/null

diff: $(output_dir)/swift-output.txt $(output_dir)/raw-output.txt $(output_dir)/character-output.txt $(output_dir)/c-output.txt
# diff will return 1 if it finds differences, which make interprets as an error
	-diff $(output_dir)/swift-output.txt $(output_dir)/raw-output.txt > $(output_dir)/raw.diff
	-diff $(output_dir)/swift-output.txt $(output_dir)/character-output.txt > $(output_dir)/character.diff
	-diff $(output_dir)/swift-output.txt $(output_dir)/c-output.txt > $(output_dir)/c.diff

# By default, running `all` will preserve the input file;
# it can be explicitly recreated with this target.
regen_input: $(build_dir)/generateInput
	$(build_dir)/generateInput $(INPUT_SIZE) | fold -w 80 -s > input.txt

clean:
	-rm -rf $(build_dir)
	-rm -rf $(output_dir)
	-rm -f input.txt

#--- Internal targets

#-- Executables

input.txt: $(build_dir)/generateInput
# Hard wrapping makes seeing diff problems a little easier; note this necessitates
# a small amout of extra work in creating the `swiftRender` tool (multiline strings)
	$(build_dir)/generateInput $(INPUT_SIZE) | fold -w 80 -s > input.txt	

$(build_dir)/raw: raw.swift | $(build_dir)
	swiftc $(optimization_flag) raw.swift -o $(build_dir)/raw
	
$(build_dir)/useCharacter: useCharacter.swift | $(build_dir)
	swiftc $(optimization_flag) useCharacter.swift -o $(build_dir)/useCharacter

$(build_dir)/c_impl: c_impl.c | $(build_dir)
	cc $(c_optimization_flag) c_impl.c -o $(build_dir)/c_impl

$(build_dir)/generateInput: generateInput.swift | $(build_dir)
	swiftc -O generateInput.swift -o $(build_dir)/generateInput

$(build_dir)/swiftRender: input.txt | $(build_dir)
	echo 'print("""' > $(build_dir)/swiftRender
	cat input.txt >> $(build_dir)/swiftRender
	echo '""")' >> $(build_dir)/swiftRender

#-- Data

$(output_dir)/swift-output.txt: input.txt $(build_dir)/swiftRender | $(output_dir)
	swift $(build_dir)/swiftRender > $(output_dir)/swift-output.txt

$(output_dir)/raw-output.txt: input.txt $(build_dir)/raw | $(output_dir)
	$(build_dir)/raw > $(output_dir)/raw-output.txt

$(output_dir)/character-output.txt: input.txt $(build_dir)/useCharacter | $(output_dir)
	$(build_dir)/useCharacter > $(output_dir)/character-output.txt

$(output_dir)/c-output.txt: input.txt $(build_dir)/c_impl | $(output_dir)
	$(build_dir)/c_impl > $(output_dir)/c-output.txt

#-- Directories

$(build_dir):
	mkdir -p $(build_dir)

$(output_dir):
	mkdir -p $(output_dir)
