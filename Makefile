NV ?= ./bin/nv

.PHONY: install fmt lint test check docs pods endpoints volumes clusters

install:
	@ln -sf "$(CURDIR)/bin/nv" /usr/local/bin/nv 2>/dev/null || echo "Add $(CURDIR)/bin to your PATH instead"

fmt:
	shfmt -i 2 -w $$(find lib commands tests -name '*.sh') bin/nv

lint:
	shellcheck lib/*.sh commands/*.sh bin/nv

test:
	bashunit tests

check: lint test

# Regenerate docs/ from the `nv doc` reference blocks in the command sources
# (scripts/gen-manual.sh reads `bin/nv doc`). Run after editing any `# doc:`
# comment so the manual stays in sync with the CLI.
docs:
	@./scripts/gen-manual.sh

pods:
	$(NV) pod list

endpoints:
	$(NV) serverless list

volumes:
	$(NV) volume list

clusters:
	$(NV) cluster list
