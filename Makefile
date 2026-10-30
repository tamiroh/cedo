APP := build/cedo.app
BIN_DIR = $(shell swift build -c release --show-bin-path)
INSTALL_DIR ?= /Applications

.PHONY: build
build:
	swift build

.PHONY: run
run:
	swift run

.PHONY: test
test:
	swift test

.PHONY: format
format:
	swift format format --in-place --recursive Package.swift Sources Tests

.PHONY: lint
lint:
	swift format lint --strict --recursive Package.swift Sources Tests

.PHONY: app
app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN_DIR)/cedo $(APP)/Contents/MacOS/cedo
	cp -R $(BIN_DIR)/SwiftTerm_SwiftTerm.bundle $(APP)/Contents/Resources/
	cp Support/Info.plist $(APP)/Contents/Info.plist
	rm -rf build/AppIcon.iconset
	mkdir -p build/AppIcon.iconset
	for size in 16 32 128 256 512; do \
		sips -z $$size $$size Support/AppIcon.png --out build/AppIcon.iconset/icon_$${size}x$${size}.png > /dev/null; \
		sips -z $$((size * 2)) $$((size * 2)) Support/AppIcon.png --out build/AppIcon.iconset/icon_$${size}x$${size}@2x.png > /dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o $(APP)/Contents/Resources/AppIcon.icns

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
