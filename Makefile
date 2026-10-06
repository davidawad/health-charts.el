EMACS ?= emacs
# eas.el, the chart engine, is a separate package: a checkout of it beside
# this one by default, overridable (make test EAS=/path/to/eas.el).  It is
# a soft dependency: without it the eas backend is unavailable, the eas
# tests skip, and the eas modules are neither compiled nor linted.
EAS ?= ../eas.el
EAS_SRC := $(wildcard $(EAS)/src/eas.el)
EAS_LOAD := $(if $(EAS_SRC),-L $(EAS)/src)
# A directory holding package-lint (e.g. an ELPA dir) for `make lint':
#   make lint PACKAGE_LINT=~/.emacs.d/elpa/package-lint-0.24
PACKAGE_LINT ?=
SOURCES := $(filter-out $(if $(EAS_SRC),,health-chart-eas%.el),$(wildcard health-chart*.el))

.PHONY: test compile checkdoc lint check clean

# test/run-tests.el loads every test/*-test.el; CI runs it directly
# where make is absent.  SELECTOR=regexp runs a subset.
test:
	$(EMACS) -Q --batch $(EAS_LOAD) -l test/run-tests.el $(if $(SELECTOR),'$(SELECTOR)')

compile:
	$(EMACS) -Q --batch -L . $(EAS_LOAD) --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile $(SOURCES)
	@rm -f *.elc

checkdoc:
	$(EMACS) -Q --batch -L . -l test/run-checkdoc.el $(SOURCES)

lint:
	$(EMACS) -Q --batch -L . $(EAS_LOAD) $(if $(PACKAGE_LINT),-L $(PACKAGE_LINT)) -l test/run-package-lint.el $(SOURCES)

check: compile checkdoc test

clean:
	rm -f *.elc
