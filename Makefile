# onit for DynamicLake
#
#   make            build a universal binary and assemble dist/Onit.dynamiclakeplugin
#   make zip        also archive it for DynamicLake Market, with SHA-256 hashes
#   make demo       print what the plugin would send for the tasks on this Mac
#   make validate   check every message against the DynamicLake app running on this Mac
#   make test       run the unit tests
#   make bead       redraw Bead's frames
#   make icon       redraw the plugin icon

PACKAGE   := Onit.dynamiclakeplugin
DIST      := dist
VERSION   := $(shell /usr/bin/python3 -c "import json;print(json.load(open('Package/$(PACKAGE)/plugin.json'))['version'])")
BIN_DIR    = $(shell swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

.PHONY: all build package zip demo validate test bead icon clean

all: package

build:
	swift build -c release --arch arm64 --arch x86_64

package: build
	rm -rf "$(DIST)/$(PACKAGE)"
	mkdir -p "$(DIST)"
	cp -R "Package/$(PACKAGE)" "$(DIST)/$(PACKAGE)"
	cp "$(BIN_DIR)/OnitLake" "$(DIST)/$(PACKAGE)/onit-lake"
	strip -x "$(DIST)/$(PACKAGE)/onit-lake"
	codesign --force --sign - "$(DIST)/$(PACKAGE)/onit-lake"
	chmod +x "$(DIST)/$(PACKAGE)/onit-lake"
	@du -sh "$(DIST)/$(PACKAGE)"

zip: package
	cd "$(DIST)" && rm -f "Onit-$(VERSION).zip" && ditto -c -k --keepParent "$(PACKAGE)" "Onit-$(VERSION).zip"
	@echo "archive SHA-256: $$(shasum -a 256 "$(DIST)/Onit-$(VERSION).zip" | cut -d' ' -f1)"
	@ls -la "$(DIST)/Onit-$(VERSION).zip"

demo:
	swift build
	DYNAMICLAKE_PLUGIN_FEATURES=lake,lakeLayout,numericText,presentSneakPeek,imageAssets \
	DYNAMICLAKE_PLUGIN_PACKAGE="$(CURDIR)/Package/$(PACKAGE)" \
	"$$(swift build --show-bin-path)/OnitLake" --demo

validate:
	@$(MAKE) -s demo 2>/dev/null | Tools/validate.py

test:
	swift test

bead:
	swift Tools/render-bead.swift "Package/$(PACKAGE)/bead"

icon:
	swift Tools/render-icon.swift "Package/$(PACKAGE)/icon.png"

clean:
	rm -rf .build "$(DIST)"
