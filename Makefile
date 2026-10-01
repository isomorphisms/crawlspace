CC ?= cc
CFLAGS ?= -std=c11 -D_GNU_SOURCE -Os -Wall -Wextra -Werror
BUILD_ID ?= $(shell git rev-parse HEAD 2>/dev/null || printf unknown)
BUILD_ID_CFLAG := -DCRAWLSPACE_BUILD_ID=\"$(BUILD_ID)\"

HOST_BUILD := build/host
HOST_BINARY := $(HOST_BUILD)/crawlspace
HOST_TEST := $(HOST_BUILD)/protocol_test

.PHONY: all test clean

all: $(HOST_BINARY)

$(HOST_BUILD):
	mkdir -p $@

$(HOST_BINARY): src/crawlspace.c | $(HOST_BUILD)
	$(CC) $(CFLAGS) $(BUILD_ID_CFLAG) -fPIE -pie $< -o $@

$(HOST_TEST): tests/protocol_test.c | $(HOST_BUILD)
	$(CC) $(CFLAGS) $< -o $@

test: $(HOST_BINARY) $(HOST_TEST)
	$(HOST_TEST) $(HOST_BINARY)
	$(HOST_BINARY) --version | grep -Fx 'crawlspace transport=2 discovery=1'

clean:
	rm -rf $(HOST_BUILD)
