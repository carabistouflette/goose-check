GOOSE ?= .toolchain/goose/build/goose
CC ?= gcc
SANITIZER_CC ?= gcc
SANITIZE ?= 0
SANITIZER_OPTION = $(if $(filter 1,$(SANITIZE)),--sanitize,)
RUN_ENV = $(if $(filter 1,$(SANITIZE)),ASAN_OPTIONS=detect_leaks=1:abort_on_error=1 UBSAN_OPTIONS=halt_on_error=1,)

.PHONY: setup format check build debug test sanitize
setup:
	./scripts/setup-goose.sh
format:
	python3 scripts/native-manifest.py
	"$(GOOSE)" format check.goose
check:
	python3 scripts/check-vendor.py
	python3 scripts/native-manifest.py --check
	"$(GOOSE)" format --check check.goose
	"$(GOOSE)" check check.goose
build: check
	mkdir -p .build
	"$(GOOSE)" build check.goose --cc "$$(python3 scripts/compiler.py --cc "$(CC)" $(SANITIZER_OPTION))" -O2 -o .build/goose-check
debug: check
	mkdir -p .build
	"$(GOOSE)" build check.goose --cc "$$(python3 scripts/compiler.py --cc "$(CC)" $(SANITIZER_OPTION))" --debug -o .build/goose-check-debug
test: build debug
	$(RUN_ENV) python3 tests/run.py --tool .build/goose-check --goose "$(abspath $(GOOSE))" --cc "$$(command -v "$(CC)")"
	$(RUN_ENV) python3 tests/run.py --tool .build/goose-check-debug --goose "$(abspath $(GOOSE))" --cc "$$(command -v "$(CC)")"
sanitize:
	$(MAKE) test test-faults CC="$(SANITIZER_CC)" SANITIZE=1 GOOSE="$(GOOSE)"

.PHONY: test-faults
test-faults: check
	mkdir -p .build
	"$(GOOSE)" build check.goose --cc "$$(python3 scripts/compiler.py --cc "$(CC)" $(SANITIZER_OPTION) --faults)" -o .build/goose-check-faults
	$(RUN_ENV) python3 tests/faults.py --tool .build/goose-check-faults

.PHONY: example analyze
example: build
	.build/goose-check --stdin "$(CURDIR)/examples/echo.c" --timeout-ms 60000 -- "$$(command -v "$(CC)")" -x c - -o "$(CURDIR)/.build/echo-example"
	python3 -c 'from pathlib import Path; Path(".build/example.bin").write_bytes(b"hello\x00Goose\xff\n")'
	.build/goose-check --stdin "$(CURDIR)/.build/example.bin" --stdout "$(CURDIR)/.build/example.bin" -- "$(CURDIR)/.build/echo-example"
analyze:
	mkdir -p .build
	clang --analyze -std=c11 -Wall -Wextra -Werror native/caller.c -o .build/caller.plist
