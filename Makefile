APP_NAME = LidGuard
BUNDLE = dist/$(APP_NAME).app
BUILD_DIR = .build/release
VERSION_FILE = VERSION
BUMP ?= patch

.PHONY: build bundle bundle-prod clean install run version icon

# Read current version
VERSION := $(shell cat $(VERSION_FILE) 2>/dev/null || echo "1.0.0")
VERSION_BASE := $(shell echo $(VERSION) | sed 's/-dev//')
IS_DEV := $(findstring -dev,$(VERSION))

build:
	swift build -c release

# Dev build: bump version, add -dev suffix
bundle: bump-version build
	@echo "Building $(APP_NAME) v$$(cat $(VERSION_FILE))-dev"
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/
	@VERSION=$$(cat $(VERSION_FILE))-dev; \
	sed -e "s/<string>1.0.0</<string>$$VERSION</" \
	    -e "s/<string>1</<string>$$(echo $$VERSION | tr -d '.-dev')</" \
	    Info.plist > $(BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/ 2>/dev/null || true
	codesign --force --sign "LidGuard" --entitlements LidGuard.entitlements \
		-o runtime --timestamp=none \
		-r='designated => certificate leaf = H"9787B7F0A9496DF5757D22D586EA8C0735656867"' \
		$(BUNDLE)
	@echo "Built: $(BUNDLE) v$$(cat $(VERSION_FILE))-dev"

# Prod build: same version, no -dev suffix
bundle-prod: build
	@echo "Building $(APP_NAME) v$$(cat $(VERSION_FILE)) (prod)"
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/
	@VERSION=$$(cat $(VERSION_FILE)); \
	sed -e "s/<string>1.0.0</<string>$$VERSION</" \
	    -e "s/<string>1</<string>$$(echo $$VERSION | tr -d '.-')</" \
	    Info.plist > $(BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/ 2>/dev/null || true
	codesign --force --sign "LidGuard" --entitlements LidGuard.entitlements \
		-o runtime --timestamp=none \
		-r='designated => certificate leaf = H"9787B7F0A9496DF5757D22D586EA8C0735656867"' \
		$(BUNDLE)
	@echo "Built: $(BUNDLE) v$$(cat $(VERSION_FILE)) (prod)"

# Bump version based on BUMP variable (major, minor, patch)
bump-version:
	@VERSION=$$(cat $(VERSION_FILE) | sed 's/-dev//'); \
	MAJOR=$$(echo $$VERSION | cut -d. -f1); \
	MINOR=$$(echo $$VERSION | cut -d. -f2); \
	PATCH=$$(echo $$VERSION | cut -d. -f3); \
	case "$(BUMP)" in \
		major) MAJOR=$$((MAJOR + 1)); MINOR=0; PATCH=0;; \
		minor) MINOR=$$((MINOR + 1)); PATCH=0;; \
		patch) PATCH=$$((PATCH + 1));; \
	esac; \
	echo "$$MAJOR.$$MINOR.$$PATCH" > $(VERSION_FILE); \
	echo "Version: $$MAJOR.$$MINOR.$$PATCH-dev"

icon:
	swift Scripts/generate_icon.swift

clean:
	rm -rf .build dist

# Install only works for prod builds
install:
	@if grep -q "\-dev" $(BUNDLE)/Contents/Info.plist; then \
		echo "Error: Cannot install dev version. Run 'make bundle-prod' first."; \
		exit 1; \
	fi
	@VERSION=$$(plutil -extract CFBundleShortVersionString raw $(BUNDLE)/Contents/Info.plist); \
	echo "Installing $(APP_NAME) v$$VERSION to /Applications"
	rm -rf /Applications/$(APP_NAME).app
	cp -r $(BUNDLE) /Applications/

run: bundle
	open $(BUNDLE)

version:
	@cat $(VERSION_FILE)
