EMACS ?= emacs
# eas.el, the chart engine, is a separate package: a checkout of it beside
# this one by default, overridable (make test EAS=/path/to/eas.el).
EAS ?= ../eas.el
LOAD_PATHS := -L $(EAS)/src -L src
SOURCES := $(filter-out %-test.el,$(wildcard src/*.el))
TESTS := $(sort $(wildcard test/*-test.el))

ERT = $(EMACS) -Q --batch $(LOAD_PATHS) -L test $(foreach t,$(1),-l $(t)) \
	--eval '(ert-run-tests-batch-and-exit (quote $(2)))'

.PHONY: test compile checkdoc goldens screenshots clean

# make test SELECTOR=regexp runs a subset.
test:
	$(call ERT,$(TESTS),$(if $(SELECTOR),"$(SELECTOR)",t))

# Rewrite every golden (or those of SELECTOR=regexp), then review the diff.
goldens:
	HEALTH_CHART_UPDATE_GOLDEN=1 $(call ERT,$(TESTS),$(if $(SELECTOR),"$(SELECTOR)",t))

compile:
	$(EMACS) -Q --batch $(LOAD_PATHS) --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile $(SOURCES)
	@find src -name '*.elc' -delete

checkdoc:
	$(EMACS) -Q --batch -L src -l test/run-checkdoc.el $(SOURCES)

# docs/screenshots/NAME.png for every template (needs rsvg-convert).
screenshots:
	$(EMACS) -Q --batch $(LOAD_PATHS) -l scripts/screenshots.el

clean:
	find src -name '*.elc' -delete
