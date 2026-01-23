APP_NAME = LidGuard
BUNDLE = dist/$(APP_NAME).app
BUILD_DIR = .build/release

.PHONY: build bundle clean install run

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/
	cp Info.plist $(BUNDLE)/Contents/
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/ 2>/dev/null || true
	codesign --force --sign "LidGuard Dev" --entitlements LidGuard.entitlements \
		-o runtime --timestamp=none \
		-r='designated => certificate leaf = H"9787B7F0A9496DF5757D22D586EA8C0735656867"' \
		$(BUNDLE)

clean:
	rm -rf .build dist

install: bundle
	rm -rf /Applications/$(APP_NAME).app
	cp -r $(BUNDLE) /Applications/

run: bundle
	open $(BUNDLE)
