MAKEFLAGS  += --no-builtin-rules
.SUFFIXES:
.SECONDARY:
.DELETE_ON_ERROR:

ARGS  ?= -v -race
PROJ  ?= github.com/johnt337/awscli
MAIN  ?= $(shell go list ./... | grep -v /vendor/)
TESTS ?= $(MAIN) -cover
LINTS ?= $(MAIN)
COVER ?=
SRC   := $(shell find . -name '*.go')
MOUNT ?= $(shell pwd)
GO15VENDOREXPERIMENT ?= 1
REGISTRY ?= johnt337

# Get the git commit
GIT_COMMIT=$(shell git rev-parse HEAD)
GIT_DIRTY=$(shell test -n "`git status --porcelain`" && echo "+CHANGES" || true)

# ECR login
ECR_TAG=latest
ECR_VERSION=$(shell grep -E 'Version =' ./cmd/ecr_login/version.go | awk '{print$$NF}' | sed 's@"@@g')

# EC2 tagging
EC2_TAG=latest
EC2_TAG_VERSION=$(shell grep -E 'Version =' ./cmd/ec2_tag/version.go | awk '{print$$NF}' | sed 's@"@@g')


build: godeps build-all

build-all:
	@make build-awscli
	@make build-ecr_login

build-awscli:
	@echo "running make build-awscli"
	docker build -t awscli-build -f Dockerfile .
	GO15VENDOREXPERIMENT=$(GO15VENDOREXPERIMENT) docker run --rm -v /var/run:/var/run -v $(MOUNT):/go/src/$(PROJ) --entrypoint=/bin/sh -i awscli-build -c "godep restore && make lint && make lint-check && make test/units && make docker/awscli "

build-ecr_login:
	@echo "running make build-ecr_login"
	docker build -t awscli-build -f Dockerfile .
	GO15VENDOREXPERIMENT=$(GO15VENDOREXPERIMENT) docker run --rm -v /var/run:/var/run -v $(MOUNT):/go/src/$(PROJ) --entrypoint=/bin/sh -i awscli-build -c "godep restore && make lint && make lint-check && make test/units && make docker/ecr_login "

build-ec2_tag:
	@echo "running make build-ec2_tag"
	docker build -t awscli-build -f Dockerfile .
	GO15VENDOREXPERIMENT=$(GO15VENDOREXPERIMENT) docker run --rm -v /var/run:/var/run -v $(MOUNT):/go/src/$(PROJ) --entrypoint=/bin/sh -i awscli-build -c "godep restore && make lint && make lint-check && make test/units && make docker/ec2_tag "

docker/awscli: $(SRC) config awscli.Dockerfile
	@echo "running make docker/awscli"
	make bin/awscli
	[ -d ./tmp ] || mkdir ./tmp && chmod 4777 ./tmp
	docker build -t $(REGISTRY)/awscli -f awscli.Dockerfile .

docker/ecr_login: $(SRC) config ecr_login.Dockerfile
	@echo "running make docker/ecr_login"
	make bin/ecr_login
	[ -d ./tmp ] || mkdir ./tmp && chmod 4777 ./tmp
	[ -d ./certs ] || cp -a /etc/ssl/certs .
	docker build -t $(REGISTRY)/ecr_login:$(ECR_VERSION) -f ecr_login.Dockerfile .
	docker build -t $(REGISTRY)/ecr_login:$(ECR_VERSION)-docker -f ecr_login_plus_docker.Dockerfile .
	docker tag -f $(REGISTRY)/ecr_login:$(ECR_VERSION) $(REGISTRY)/ecr_login:$(ECR_TAG)

docker/ec2_tag: $(SRC) config ec2_tag.Dockerfile
	@echo "running make docker/tag"
	make bin/ec2_tag
	[ -d ./tmp ] || mkdir ./tmp && chmod 4777 ./tmp
	[ -d ./certs ] || cp -a /etc/ssl/certs .
	docker build -t $(REGISTRY)/ec2_tag:$(EC2_TAG_VERSION) -f ec2_tag.Dockerfile .
	docker tag -f $(REGISTRY)/ec2_tag:$(EC2_TAG_VERSION) $(REGISTRY)/ec2_tag:$(EC2_TAG)

docker/push:
	docker push $(REGISTRY)/ecr_login:$(ECR_VERSION)
	docker push $(REGISTRY)/ecr_login:$(ECR_VERSION)-docker
	docker push $(REGISTRY)/ecr_login:$(ECR_TAG)
	docker push $(REGISTRY)/ec2_tag:$(EC2_TAG_VERSION)
	docker push $(REGISTRY)/ec2_tag:$(EC2_TAG)

bin: $(SRC)
	@make bin/awscli
	@make bin/ecr_login
	@make bin/ec2_tag

bin/awscli: $(SRC)
	@echo "statically linking awscli"
	CGO_ENABLED=0 GOOS=linux godep go build -a -installsuffix cgo -ldflags '-w -X main.GitCommit=$(GIT_COMMIT)$(GIT_DIRTY)' -o bin/awscli cmd/awscli/*.go

bin/ecr_login: $(SRC)
	@echo "statically linking ecr_login"
	CGO_ENABLED=0 GOOS=linux godep go build -a -installsuffix cgo -ldflags '-w -X main.GitCommit=$(GIT_COMMIT)$(GIT_DIRTY)' -o bin/ecr_login cmd/ecr_login/*.go

bin/ec2_tag: $(SRC)
	@echo "statically linking ec2_tag"
	CGO_ENABLED=0 GOOS=linux godep go build -a -installsuffix cgo -ldflags '-w -X main.GitCommit=$(GIT_COMMIT)$(GIT_DIRTY)' -o bin/ec2_tag cmd/ec2_tag/*.go


bootstrap:
	ginkgo bootstrap

bootstrap-test:
	@cd ${DIR} && ginkgo bootstrap && cd ~-

godeps:
	@echo "running godep"
	godep save ./...

clean:
	@echo "running make clean"
	rm -f bin/awscli bin/ecr_login bin/ec2_tag
	docker images | grep -E '<none>' | awk '{print$$3}' | xargs docker rmi

distclean:
	@make clean
	@echo "running make distclean"
	rm -rf ./tmp ./certs
	docker rm awscli-build run-awscli
	docker rmi awscli-build $(REGISTRY)/awscli $(REGISTRY)/ecr_login $(REGISTRY)/ec2_tag

interactive:
	@echo "running make interactive build"
	docker build -t awscli-build -f Dockerfile .
	docker run -it --rm --name awscli-build -v /var/run:/var/run -v $(MOUNT):/go/src/$(PROJ) --entrypoint=/bin/bash -i awscli-build

lint: $(SRC)
	@for pkg in $(LINTS); do echo "linting: $$pkg"; golint $$pkg; done

lint-check: $(SRC)
	@for pkg in $(LINTS); do \
		echo -n "linting: $$pkg: "; \
		echo "`golint $$pkg | wc -l | awk '{print$$NF}'` error(s)"; \
		[ $$(golint $$pkg | wc -l | awk '{print$$NF}') -le 0 ] && true || false; \
	done

run-awscli: config
	@echo "running bin/awscli"
	docker run -it --rm -i $(REGISTRY)/awscli

run-ecr_login: config
	@echo "running bin/ecr_login"
	docker run -it --rm -i $(REGISTRY)/ecr_login

run-ec2_tag: config
	@echo "running bin/ec2_tag"
	docker run -it --rm -i $(REGISTRY)/ec2_tag

test:
	@echo "running test"
	docker run -it --rm -v /var/run:/var/run -v $(MOUNT):/go/src/$(PROJ) --entrypoint=/bin/sh -i awscli-build -c "godep restore && make test/units"

test/units: $(SRC)
	@echo "running test/units"
	godep go test $(TESTS) $(ARGS)

test-cover: $(SRC)
	@godep go test $(COVER) -coverprofile=coverage.out
	@godep go tool cover -html=coverage.out

vet: $(SRC)
	@for pkg in $(LINTS); do echo "vetting: $$pkg"; godep go vet $$pkg; done

.PHONY: clean test test/units run-bin/awscli run-bin/ecr_login run-bin/ec2_tag interactive bootstrap bootstrap-test lint lint-check test-cover godeps docker/push
