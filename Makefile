.PHONY: build
build:
	@echo "Building hugo site"
	hugo --destination docs

.PHONY: serve
serve:
	hugo server -D
