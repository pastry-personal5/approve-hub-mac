.DEFAULT_GOAL := build

.PHONY: build run test format lint contract-check check

build:
	swift build

run:
	swift run approve-hub

test:
	swift test

format:
	swift format --in-place --recursive Sources Tests

lint:
	swiftlint lint --strict

contract-check:
	ruby Tests/ContractValidation/validate.rb

check:
	swift format lint --strict --recursive Sources Tests
	swiftlint lint --strict
	swift test
	$(MAKE) contract-check
