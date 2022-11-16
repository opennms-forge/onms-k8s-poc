RELEASE                ?= latest # could also use a tag like tags/v2.0.1

GITHUB_API_RELEASE_URL ?= https://api.github.com/repos/$(GITHUB_PROJECT)/releases/$(RELEASE)

# Note: if you get 403 errors but are passing a valid $(RELEASE), you have probably been ratelimited by GitHub
# See: https://docs.github.com/en/rest/overview/resources-in-the-rest-api#checking-your-rate-limit-status
VERSION                ?= $(shell curl -sSf $(GITHUB_API_RELEASE_URL) | jq -r .tag_name | sed 's/^v//')
DOWNLOAD_URL           ?= $(shell curl -sSf $(GITHUB_API_RELEASE_URL) | jq -r '.assets[] | select(.name | endswith(".kar")) | .browser_download_url')

.PHONY: check download build push

.DEFAULT_GOAL := build

# Make sure we got something for the version and our curl calls above didn't fail
check:
	test -n "$(VERSION)"
	test -n "$(DOWNLOAD_URL)"

download: check
	mkdir -p build
	curl -sSf -LJ -o build/$(TARGET_KAR_NAME) $(DOWNLOAD_URL)

build: download
	docker build \
		--build-arg TARGET_KAR_NAME=$(TARGET_KAR_NAME) \
		-t $(DOCKER_IMAGE):$(VERSION) \
		-f ../Dockerfile .

push:
	docker push $(DOCKER_IMAGE):$(VERSION)

clean:
	rm -rf build
