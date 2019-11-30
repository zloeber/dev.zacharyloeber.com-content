## Allow easy commits of this project
GIT_BRANCH ?= master
GIT_COMMIT_MESSAGE ?= Generate site

.PHONY: help commit publish
help: ## This help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
.DEFAULT_GOAL := help

commit: ## Commit destiniation repository
	git add .
	git commit -m "${GIT_COMMIT_MESSAGE}"
	git push origin "${GIT_BRANCH}"
