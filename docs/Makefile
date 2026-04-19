### Trading docs — soupault build ###

BUILD_DIR := _site
SOUPAULT  := soupault
PORT      ?= 8000

.PHONY: all
all: site

.PHONY: site
site:
	$(SOUPAULT)

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

.PHONY: serve
.ONESHELL: serve
serve: site
	cd $(BUILD_DIR)
	@echo "Serving docs at http://localhost:$(PORT)/"
	python3 -m http.server $(PORT)

.PHONY: watch
watch:
	@command -v entr >/dev/null 2>&1 || { \
	  echo "entr not installed; install it for auto-rebuild"; exit 1; }
	find . -type f \( -name '*.md' -o -name '*.toml' -o -name '*.html' \
	                  -o -name '*.css' -o -name '*.lua' \) \
	  | grep -v '^\./$(BUILD_DIR)/' \
	  | entr -r make site
