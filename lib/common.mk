# Common Makefile parts for BPF-building with libbpf
# --------------------------------------------------
# SPDX-License-Identifier: (GPL-2.0 OR BSD-2-Clause)
#
# This file should be included from your Makefile like:
#  LIB_DIR = ../lib/
#  include $(LIB_DIR)/common.mk
#
# It is expected that you define the variables:
#  XDP_TARGETS and USER_TARGETS
# as a space-separated list
#
XDP_C = ${XDP_TARGETS:=.c}
XDP_OBJ = ${XDP_C:.c=.o}
USER_C := ${USER_TARGETS:=.c}
USER_OBJ := ${USER_C:.c=.o}

# Expect this is defined by including Makefile, but define if not
LIB_DIR ?= ../lib
LDLIBS ?= $(USER_LIBS)

include $(LIB_DIR)/defines.mk

# get list of objects in util
include $(LIB_DIR)/util/util.mk

# Extend if including Makefile already added some
LIB_OBJS += $(foreach obj,$(UTIL_OBJS),$(LIB_DIR)/util/$(obj))

# Create expansions for dependencies
LIB_H := ${LIB_OBJS:.o=.h}

EXTRA_DEPS +=
EXTRA_USER_DEPS +=

# BPF-prog kern and userspace shares struct via header file:
KERN_USER_H ?= $(wildcard common_kern_user.h)

CFLAGS += -I../headers/ -I$(LIB_DIR)/util
BPF_CFLAGS += -I../headers/

BPF_HEADERS := $(wildcard ../headers/bpf/*.h)

all: $(USER_TARGETS) $(XDP_OBJ)

.PHONY: clean

clean:
	$(Q)rm -f $(USER_TARGETS) $(XDP_OBJ) $(USER_OBJ)
	$(Q)rm -f *.ll
	$(Q)rm -f *~

install:
	install -m 0755 -d $(DESTDIR)$(SBINDIR)
	install -m 0755 -d $(DESTDIR)$(BPF_OBJECT_DIR)
	install -m 0755 $(USER_TARGETS) $(DESTDIR)$(SBINDIR)
	install -m 0644 $(XDP_OBJ) $(DESTDIR)$(BPF_OBJECT_DIR)

$(OBJECT_LIBBPF):
	$(Q)$(MAKE) $(MFLAGS) -C $(LIB_DIR) libbpf

# Create dependency: detect if C-file change and touch H-file, to trigger
# target $(LIB_OBJS)
$(LIB_H): %.h: %.c
	touch $@

# Detect if any of common obj changed and create dependency on .h-files
$(LIB_OBJS): %.o: %.h
	make -C $(LIB_DIR)

$(USER_TARGETS): %: %.c  $(OBJECT_LIBBPF) $(MAKEFILES) $(LIB_OBJS) $(KERN_USER_H) $(EXTRA_DEPS) $(EXTRA_USER_DEPS)
	$(QUIET_CC)$(CC) -Wall $(CFLAGS) $(LDFLAGS) -o $@ $(LIB_OBJS) \
	 $< $(LDLIBS)

$(XDP_OBJ): %.o: %.c $(KERN_USER_H) $(EXTRA_DEPS) $(BPF_HEADERS) $(MAKEFILES)
	$(QUIET_CLANG)$(CLANG) -S \
	    -target bpf \
	    -D __BPF_TRACING__ \
	    $(BPF_CFLAGS) \
	    -Wall \
	    -Wno-unused-value \
	    -Wno-pointer-sign \
	    -Wno-compare-distinct-pointer-types \
	    -Werror \
	    -O2 -emit-llvm -c -g -o ${@:.o=.ll} $<
	$(QUIET_LLC)$(LLC) -march=bpf -filetype=obj -o $@ ${@:.o=.ll}
