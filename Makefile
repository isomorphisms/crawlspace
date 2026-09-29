CC ?= cc
CFLAGS ?= -std=c11 -D_GNU_SOURCE -Os -Wall -Wextra -Werror

HOST_BUILD := build/host
HOST_BINARY := $(HOST_BUILD)/crawlspace
HOST_TEST := $(HOST_BUILD)/protocol_test

.PHONY: all test clean

all: $(HOST_BINARY)

$(HOST_BUILD):
	mkdir -p $@

$(HOST_BINARY): src/crawlspace.c | $(HOST_BUILD)
	$(CC) $(CFLAGS) -fPIE -pie $< -o $@

$(HOST_TEST): tests/protocol_test.c | $(HOST_BUILD)
	$(CC) $(CFLAGS) $< -o $@

test: $(HOST_BINARY) $(HOST_TEST)
	$(HOST_TEST) $(HOST_BINARY)

clean:
	rm -rf $(HOST_BUILD)
