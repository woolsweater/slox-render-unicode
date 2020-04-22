.PHONY: all clean time regen_input

# Number of text segments in the generated input text, each of which
# will have some size variation. 100,000 produces a file of a few
# megabytes.
INPUT_SIZE ?= 100000

BUILD_DIR = ./build
	
#--- Targets to be run as "commands"

all: input.txt $(BUILD_DIR)/raw $(BUILD_DIR)/useCharacter

time: input.txt $(BUILD_DIR)/raw $(BUILD_DIR)/useCharacter
	time $(BUILD_DIR)/raw >/dev/null
	time $(BUILD_DIR)/useCharacter >/dev/null

# By default, running `all` will preserve the input file;
# it can be explicitly recreated with this target.
regen_input: $(BUILD_DIR)/generateInput
	$(BUILD_DIR)/generateInput $(INPUT_SIZE) > input.txt

clean:
	-rm -rf $(BUILD_DIR)
	-rm -f input.txt

#--- Internal targets

input.txt: $(BUILD_DIR)/generateInput
	$(BUILD_DIR)/generateInput $(INPUT_SIZE) > input.txt

$(BUILD_DIR)/raw: raw.swift | build
	swiftc raw.swift -o $(BUILD_DIR)/raw
	
$(BUILD_DIR)/useCharacter: useCharacter.swift | $(BUILD_DIR)
	swiftc useCharacter.swift -o $(BUILD_DIR)/useCharacter

$(BUILD_DIR)/generateInput: generateInput.swift | $(BUILD_DIR)
	swiftc generateInput.swift -o $(BUILD_DIR)/generateInput

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)
