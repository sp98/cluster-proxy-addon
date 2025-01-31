all: build
.PHONY: all

export GOPATH ?= $(shell go env GOPATH)

# Include the library makefile
include $(addprefix ./vendor/github.com/openshift/build-machinery-go/make/, \
	golang.mk \
	targets/openshift/deps.mk \
	targets/openshift/images.mk \
	targets/openshift/bindata.mk \
	lib/tmp.mk \
)

# Image URL to use all building/pushing image targets;
IMAGE ?= cluster-proxy-addon
IMAGE_REGISTRY ?= quay.io/open-cluster-management

# ANP source code
ANP_NAME ?= apiserver-network-proxy
ANP_VERSION ?= 0.0.24
ANP_SRC_CODE ?= dependencymagnet/${ANP_NAME}/${ANP_VERSION}.tar.gz

# Add packages to do unit test
GO_TEST_PACKAGES :=./pkg/...
KUBECTL ?= kubectl

# This will call a macro called "build-image" which will generate image specific targets based on the parameters:
# $0 - macro name
# $1 - target suffix
# $2 - Dockerfile path
# $3 - context directory for image build
# It will generate target "image-$(1)" for building the image and binding it as a prerequisite to target "images".
$(call build-image,$(IMAGE),$(IMAGE_REGISTRY)/$(IMAGE),./Dockerfile,.)

$(call add-bindata,addon-agent,./pkg/hub/addon/manifests/...,bindata,bindata,./pkg/hub/addon/bindata/bindata.go)

build-all: build build-anp
.PHONY: build-all

build-anp:
	mkdir -p $(PERMANENT_TMP)
	cp $(ANP_SRC_CODE) $(PERMANENT_TMP)/$(ANP_NAME).tar.gz
	cd $(PERMANENT_TMP) && tar -xf $(ANP_NAME).tar.gz
	cp -r vendor $(PERMANENT_TMP)/$(ANP_NAME)
	cd $(PERMANENT_TMP)/$(ANP_NAME) && mv modules.txt.bak vendor/modules.txt
	cd $(PERMANENT_TMP)/$(ANP_NAME) && rm -rf vendor/sigs.k8s.io/apiserver-network-proxy
	cd $(PERMANENT_TMP)/$(ANP_NAME) && go build -o proxy-agent cmd/agent/main.go
	cd $(PERMANENT_TMP)/$(ANP_NAME) && go build -o proxy-server cmd/server/main.go
	mv $(PERMANENT_TMP)/$(ANP_NAME)/proxy-agent ./
	mv $(PERMANENT_TMP)/$(ANP_NAME)/proxy-server ./
.PHONY: build-anp

# e2e
build-e2e: 
	go test -c ./test/e2e
.PHONY: build-e2e

deploy-ocm:
	test/install-ocm.sh
.PHONY: deploy-ocm

deploy-addon-for-e2e:
	test/install-addon.sh
.PHONY: deploy-addon-for-e2e

clean-addon-for-e2e:
	test/uninstall-addon.sh
.PHONY: clean-addon-for-e2e

test-e2e: deploy-ocm deploy-addon-for-e2e build-e2e
	export CLUSTER_BASE_DOMAIN=$(shell $(KUBECTL) get ingress.config.openshift.io cluster -o=jsonpath='{.spec.domain}') && ./e2e.test -test.v -ginkgo.v
.PHONY: test-e2e
