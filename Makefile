EXECUTE_WITH_ENV = $(PWD)/scripts/env/inject-env.sh
export PATH := $(shell pwd)/node_modules/.bin:$(PATH)

## Commands
test:
	${EXECUTE_WITH_ENV} \
		'env | grep -e SHARED_CONFIG -e TENANT_CONFIG -e SHARED_SECRET -e TENANT_SECRET | grep -v export'

test-ci:
	CI=true ${EXECUTE_WITH_ENV} \
		'env | grep -e SHARED_CONFIG -e TENANT_CONFIG -e SHARED_SECRET -e TENANT_SECRET | grep -v export'

.PHONY: test
