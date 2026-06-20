.PHONY: help init plan apply test lint

help: ## Show this help
    @grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize terragrunt for dev environment
    cd infra/environments/dev && terragrunt run-all init

plan: ## Plan infrastructure changes for dev
    cd infra/environments/dev && terragrunt run-all plan

apply: ## Apply infrastructure changes for dev
    cd infra/environments/dev && terragrunt run-all apply

test: ## Run Python unit tests
    pytest tests/ -v

lint: ## Run Python linter
    ruff check src/