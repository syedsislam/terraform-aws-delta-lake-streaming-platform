# =============================================================================
# Shortcuts for the standard Terraform workflow.
# Usage: make init ENV=dev | make plan ENV=dev | make apply ENV=prod ...
# The backend config file (backend.<env>.hcl) must exist — see backend.hcl.example.
# =============================================================================

ENV ?= dev
TFVARS = environments/$(ENV).tfvars
BACKEND_CFG = backend.$(ENV).hcl

.PHONY: init fmt validate plan apply destroy output clean

init:
	terraform init -backend-config=$(BACKEND_CFG)

fmt:
	terraform fmt -recursive

validate:
	terraform validate

plan:
	terraform plan -var-file=$(TFVARS) -out=tfplan

apply:
	terraform apply tfplan

destroy:
	terraform destroy -var-file=$(TFVARS)

output:
	terraform output

clean:
	rm -f tfplan
	rm -rf .terraform
