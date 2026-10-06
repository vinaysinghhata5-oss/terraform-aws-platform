# Usage: make plan ENV=dev
ENV ?= dev
DIR := envs/$(ENV)

.PHONY: help fmt validate lint scan init plan apply lock bootstrap

help:
	@grep -E '^[a-z]+:' Makefile | cut -d: -f1

fmt:
	terraform fmt -recursive

validate:
	@for d in envs/dev envs/qa envs/prod bootstrap; do \
		terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d validate || exit 1; \
	done

lint:
	tflint --init && tflint --recursive --config $(CURDIR)/.tflint.hcl

scan:
	checkov --config-file .checkov.yaml -d .

init:
	terraform -chdir=$(DIR) init

plan: init
	terraform -chdir=$(DIR) plan -out=tfplan

# Local apply is for break-glass only - normal path is the GitHub Actions pipeline.
apply:
	terraform -chdir=$(DIR) apply tfplan

# Pin provider hashes for every platform CI and engineers use; commit the result.
lock:
	@for d in envs/dev envs/qa envs/prod bootstrap; do \
		terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
		terraform -chdir=$$d providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64; \
	done

bootstrap:
	terraform -chdir=bootstrap init && terraform -chdir=bootstrap apply -var-file=$(ENV).tfvars
