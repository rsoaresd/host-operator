############################################################
#
# (local) Tests
#
############################################################

.PHONY: test
## runs the tests without coverage and excluding E2E tests
test: generate
	@echo "running the tests without coverage and excluding E2E tests..."
	$(Q)go test ${V_FLAG} -race $(shell go list ./... | grep -v /test/e2e) -failfast


############################################################
#
# OpenShift CI Tests with Coverage
#
############################################################

# Output directory for coverage information
COV_DIR = $(OUT_DIR)/coverage

.PHONY: test-with-coverage
## runs the tests with coverage
test-with-coverage: generate
	@echo "running the tests with coverage..."
	@-mkdir -p $(COV_DIR)
	@-rm $(COV_DIR)/coverage.txt
	$(Q)go test -vet off ${V_FLAG} $(shell go list ./... | grep -v /cmd/manager) -coverprofile=$(COV_DIR)/coverage.txt -covermode=atomic ./...

.PHONY: upload-codecov-report
# Uploads the test coverage reports to codecov.io. 
# DO NOT USE LOCALLY: must only be called by OpenShift CI when processing new PR and when a PR is merged! 
upload-codecov-report: 
	# Upload coverage to codecov.io. Since we don't run on a supported CI platform (Jenkins, Travis-ci, etc.), 
	# we need to provide the PR metadata explicitely using env vars used coming from https://github.com/openshift/test-infra/blob/master/prow/jobs.md#job-environment-variables
	# 
	# Also: not using the `-F unittests` flag for now as it's temporarily disabled in the codecov UI 
	# (see https://docs.codecov.io/docs/flags#section-flags-in-the-codecov-ui)
	env
ifneq ($(PR_COMMIT), null)
	@echo "uploading test coverage report for pull-request #$(PULL_NUMBER)..."
	bash <(curl -s https://codecov.io/bash) \
		-t $(CODECOV_TOKEN) \
		-f $(COV_DIR)/coverage.txt \
		-C $(PR_COMMIT) \
		-r $(REPO_OWNER)/$(REPO_NAME) \
		-P $(PULL_NUMBER) \
		-Z
else
	@echo "uploading test coverage report after PR was merged..."
	bash <(curl -s https://codecov.io/bash) \
		-t $(CODECOV_TOKEN) \
		-f $(COV_DIR)/coverage.txt \
		-C $(BASE_COMMIT) \
		-r $(REPO_OWNER)/$(REPO_NAME) \
		-Z
endif

CODECOV_TOKEN := "e0747034-8ed2-4165-8d0b-3015d94307f9"
REPO_OWNER := $(shell echo $$CLONEREFS_OPTIONS | jq '.refs[0].org')
REPO_NAME := $(shell echo $$CLONEREFS_OPTIONS | jq '.refs[0].repo')
BASE_COMMIT := $(shell echo $$CLONEREFS_OPTIONS | jq '.refs[0].base_sha')
PR_COMMIT := $(shell echo $$CLONEREFS_OPTIONS | jq '.refs[0].pulls[0].sha')
PULL_NUMBER := $(shell echo $$CLONEREFS_OPTIONS | jq '.refs[0].pulls[0].number')

###########################################################
#
# End-to-end Tests
#
###########################################################

E2E_REPO_PATH := ""

.PHONY: test-e2e-local
test-e2e-local: generate
	$(MAKE) test-e2e E2E_REPO_PATH=../toolchain-e2e

.PHONY: publish-current-bundles-for-e2e
publish-current-bundles-for-e2e: generate get-e2e-repo
	# build & publish the bundles via toolchain-e2e repo
	$(MAKE) -C ${E2E_REPO_PATH} get-and-publish-operators HOST_REPO_PATH=${PWD}

.PHONY: test-e2e
test-e2e: generate get-e2e-repo
	# run the e2e test via toolchain-e2e repo
	$(MAKE) -C ${E2E_REPO_PATH} test-e2e HOST_REPO_PATH=${PWD}

PAIRING_DIR := "/tmp/pairing"
PAIRING_EXEC := "/tmp/pairing/pairing"
TOOLCHAIN_CICD := "/tmp/toolchain-cicd"

.PHONY: build-pairing
build-pairing:
	# Clean the directory if it exists
	if [ -d "${TOOLCHAIN_CICD}" ]; then rm -rf ${TOOLCHAIN_CICD}; fi
	# Clone 
	git clone --branch add_pairing_go_script https://github.com/rsoaresd/toolchain-cicd.git ${TOOLCHAIN_CICD}
	# Build the Go binary into the specified directory
	make -C ${TOOLCHAIN_CICD}/scripts/ci/pairing build-pairing PAIRING_DIR=${PAIRING_DIR}

.PHONY: get-e2e-repo
get-e2e-repo: build-pairing
get-e2e-repo:
ifeq ($(E2E_REPO_PATH),"")
	$(eval E2E_REPO_PATH = /tmp/toolchain-e2e)
	${PAIRING_EXEC} -clone-dir ${E2E_REPO_PATH} -organization codeready-toolchain -repository host-operator

.PHONY: clean-e2e-namespaces
clean-e2e-namespaces:
	$(Q)-oc get projects --output=name | grep -E "(member|host)\-operator\-[0-9]+|toolchain\-e2e\-[0-9]+" | xargs oc delete
