# Unix / macOS / MSYS2 MinGW: GNU make + PGXS.
# Official Windows (EDB / Visual Studio): scripts/build-msvc.bat (win32/nmake.mak).
EXTENSION = plecl
MODULE_big = plecl
OBJS = src/plecl.o src/convert.o src/spi.o
DATA = sql/plecl--0.1.0.sql
PGFILEDESC = "plecl - Common Lisp (ECL) procedural language"

PG_CONFIG ?= pg_config
# Ubuntu PGXS also builds LLVM bitcode; ECL headers trip -Werror there.
with_llvm = no

ECL_CONFIG ?= ecl-config
ECL_CFLAGS ?= $(shell command -v $(ECL_CONFIG) >/dev/null && $(ECL_CONFIG) --cflags)
ECL_LIBS ?= $(shell command -v $(ECL_CONFIG) >/dev/null && $(ECL_CONFIG) --libs)
ifeq ($(ECL_CFLAGS),)
  ECL_CFLAGS :=
  ECL_LIBS := -lecl -lgc -lgmp -lm -lpthread
endif
# Homebrew ecl-config --cflags lists gmp but not bdw-gc; ecl/config.h includes <gc/gc.h>.
BDWGC_CFLAGS ?= $(shell pkg-config --cflags bdw-gc 2>/dev/null)
ifeq ($(BDWGC_CFLAGS),)
  BREW_BDWGC := $(shell command -v brew >/dev/null 2>&1 && brew --prefix bdw-gc 2>/dev/null)
  ifneq ($(BREW_BDWGC),)
    BDWGC_CFLAGS := -I$(BREW_BDWGC)/include
  endif
endif
# Must be set before include $(PGXS) — Homebrew PGXS snapshots CPPFLAGS at include time.
PG_CPPFLAGS += $(ECL_CFLAGS) $(BDWGC_CFLAGS) -I$(srcdir)/src
SHLIB_LINK += $(ECL_LIBS)

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

override PG_CFLAGS += -Wno-declaration-after-statement

.PHONY: install-lisp dist
install: install-lisp

dist:
	$(SHELL) "$(srcdir)/scripts/pack-release.sh" $(or $(PLATFORM),linux-x86_64)

install-lisp:
	$(MKDIR_P) '$(DESTDIR)$(pkglibdir)'
	$(INSTALL_DATA) $(srcdir)/lisp/plecl.lisp '$(DESTDIR)$(pkglibdir)/plecl.lisp'
	$(INSTALL_DATA) $(srcdir)/lisp/inspect.lisp '$(DESTDIR)$(pkglibdir)/inspect.lisp'
	$(INSTALL_DATA) $(srcdir)/lisp/blob.lisp '$(DESTDIR)$(pkglibdir)/blob.lisp'
	$(INSTALL_DATA) $(srcdir)/vendor/asdf.lisp '$(DESTDIR)$(pkglibdir)/asdf.lisp'
