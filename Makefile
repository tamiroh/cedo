APP := build/cedo.app
BIN = $(shell swift build -c release --show-bin-path)/cedo
INSTALL_DIR ?= /Applications

.PHONY: build
build:
	swift build

.PHONY: run
run:
	swift run

.PHONY: app
app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BIN) $(APP)/Contents/MacOS/cedo
	cp Support/Info.plist $(APP)/Contents/Info.plist

.PHONY: open
open: app
	open $(APP)

.PHONY: install
install: app
	rm -rf $(INSTALL_DIR)/cedo.app
	cp -R $(APP) $(INSTALL_DIR)/

.PHONY: clean
clean:
	swift package clean
	rm -rf build
