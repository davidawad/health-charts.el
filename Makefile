EMACS ?= emacs
# A directory holding package-lint (e.g. an ELPA dir) for `make lint':
#   make lint PACKAGE_LINT=~/.emacs.d/elpa/package-lint-0.24
PACKAGE_LINT ?=
SOURCES := $(wildcard health-chart*.el)

.PHONY: test compile checkdoc lint check clean

# test/run-tests.el loads every test/*-test.el; CI runs it directly
# where make is absent.  SELECTOR=regexp runs a subset.
test:
	$(EMACS) -Q --batch -l test/run-tests.el $(if $(SELECTOR),'$(SELECTOR)')

compile:
	$(EMACS) -Q --batch -L . --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile $(SOURCES)
	@rm -f *.elc

checkdoc:
	$(EMACS) -Q --batch -L . -l test/run-checkdoc.el $(SOURCES)

lint:
	$(EMACS) -Q --batch -L . $(if $(PACKAGE_LINT),-L $(PACKAGE_LINT)) -l test/run-package-lint.el $(SOURCES)

check: compile checkdoc test

clean:
	rm -f *.elc
