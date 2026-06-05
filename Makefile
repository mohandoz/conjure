PREFIX  ?= $(HOME)/.local
BINDIR  ?= $(PREFIX)/bin
REPO_ROOT := $(CURDIR)

.PHONY: help install uninstall

help:
	@printf "Conjure — local development install targets\n"
	@printf "\n"
	@printf "  make install          Symlink cli/conjure into BINDIR (live-reload, no copy)\n"
	@printf "  make uninstall        Remove the symlink from BINDIR\n"
	@printf "  make help             Show this message\n"
	@printf "\n"
	@printf "Variables (override on command line):\n"
	@printf "  PREFIX=%s\n" "$(PREFIX)"
	@printf "  BINDIR=%s\n" "$(BINDIR)"

install:
	@chmod +x $(REPO_ROOT)/cli/conjure
	@mkdir -p $(BINDIR)
	@ln -sf $(REPO_ROOT)/cli/conjure $(BINDIR)/conjure
	@printf "installed: %s -> %s\n" "$(BINDIR)/conjure" "$(REPO_ROOT)/cli/conjure"
	@case ":$$PATH:" in \
	  *":$(BINDIR):"*) printf "  conjure version: $$($(BINDIR)/conjure version)\n" ;; \
	  *) printf "  NOTE: $(BINDIR) is not on PATH. Add to your shell rc:\n"; \
	     printf "    export PATH=\"$(BINDIR):$$PATH\"\n" ;; \
	esac

uninstall:
	@rm -f $(BINDIR)/conjure
	@printf "uninstalled: %s\n" "$(BINDIR)/conjure"
