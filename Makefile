include .env

.PHONY: build tests

build:
	forge build

tests:
	forge test -vvvv
