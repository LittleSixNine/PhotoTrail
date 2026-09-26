.DEFAULT_GOAL := build
.PHONY: project build test test-localization test-map test-unit test-packages clean
NODE ?= node

project:
	xcodegen generate

build: project
	xcodebuild -project PhotoTrail.xcodeproj -scheme PhotoTrail \
		-configuration Debug -destination 'platform=macOS' build

test: test-localization test-map test-unit test-packages

test-localization:
	python3 scripts/test-localization.py

test-map:
	$(NODE) --test scripts/test-amap.mjs

test-unit: project
	xcodebuild -project PhotoTrail.xcodeproj -scheme PhotoTrail \
		-destination 'platform=macOS' -derivedDataPath Build/Tests \
		PHOTOTRAIL_BUNDLE_ID=local.PhotoTrail.Validation \
		-only-testing:PhotoTrailTests test

test-packages:
	@set -e; for package in Packages/*; do swift test --package-path "$$package"; done

clean: project
	xcodebuild -project PhotoTrail.xcodeproj -scheme PhotoTrail clean
