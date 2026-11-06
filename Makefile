APP_NAME := MarkDownGo
CONFIG ?= Release
DERIVED := build
VERSION := $(shell awk '/MARKETING_VERSION:/ {gsub(/"/,""); print $$2; exit}' project.yml)

.PHONY: project build test dmg run sign icon clean

project:
	xcodegen generate

build: project
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration $(CONFIG) -derivedDataPath $(DERIVED) ARCHS=arm64 CODE_SIGN_IDENTITY=- build
	scripts/strip-and-sign.sh $(CONFIG)

test: project
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Debug -derivedDataPath $(DERIVED) ARCHS=arm64 test

dmg: build
	scripts/make-dmg.sh "$(VERSION)"

run: build
	open $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app

icon:
	scripts/make-appicon.sh

sign:
	scripts/sign-local.sh

clean:
	rm -rf $(DERIVED) dist
