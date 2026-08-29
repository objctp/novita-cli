NV ?= ./bin/nv

.PHONY: install fmt lint test check docs hooks changelog release package pods endpoints volumes clusters

install:
	@ln -sf "$(CURDIR)/bin/nv" /usr/local/bin/nv 2>/dev/null || echo "Add $(CURDIR)/bin to your PATH instead"

fmt:
	shfmt -i 2 -w $$(find lib commands tests -name '*.sh') bin/nv install.sh

lint:
	shellcheck lib/*.sh commands/*.sh bin/nv install.sh scripts/*.sh .githooks/*

test:
	bashunit tests

check: lint test

# Regenerate docs/ from the `nv doc` reference blocks in the command sources
# (scripts/gen-manual.sh reads `bin/nv doc`). Run after editing any `# doc:`
# comment so the manual stays in sync with the CLI.
docs:
	@./scripts/gen-manual.sh

# Point git at the committed hooks in .githooks (the pre-commit hook
# regenerates docs/ and stages it; the post-commit hook folds changelog
# entries into the commit). Run once per clone; it sets core.hooksPath
# locally, which only affects this repo.
hooks:
	git config core.hooksPath .githooks
	@echo "git hooks now resolve from .githooks (pre-commit syncs docs/, post-commit syncs CHANGELOG.md)"

# Rewrite the Unreleased changelog section from conventional commits
# (scripts/changelog.sh; requires git-cliff).
changelog:
	@./scripts/changelog.sh unreleased

# Cut a release: version section + commit + tag. Usage: make release VERSION=1.0.0
release:
	@./scripts/changelog.sh release $(VERSION)

# Build the release tarball + SHA256SUMS locally, mirroring the
# .github/workflows/release.yml steps (version stamped into a staged copy so the
# working tree's lib/_version.sh placeholder is left untouched). Run without a
# git tag to inspect the artefact shape before publishing.
package:
	@set -e; \
	VERSION=$$(git describe --tags --always 2>/dev/null | sed 's/-.*//' || true); \
	[ -n "$$VERSION" ] || VERSION=0.0.0-dev; \
	STAGE=$$(mktemp -d); \
	trap "rm -rf $$STAGE" EXIT; \
	cp -R bin lib commands LICENSE "$$STAGE"/; \
	printf 'NV_VERSION="%s"\n' "$$VERSION" > "$$STAGE/lib/_version.sh"; \
	tar czf "nv-$$VERSION.tar.gz" -C "$$STAGE" bin lib commands LICENSE; \
	shasum -a 256 "nv-$$VERSION.tar.gz" > SHA256SUMS; \
	echo "built nv-$$VERSION.tar.gz + SHA256SUMS"

pods:
	$(NV) pod list

endpoints:
	$(NV) serverless list

volumes:
	$(NV) volume list

clusters:
	$(NV) cluster list
