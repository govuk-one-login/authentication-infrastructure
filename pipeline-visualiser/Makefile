.DEFAULT: run

define sso_login
	export AWS_PROFILE=di-authentication-development-AdministratorAccessPermission; \
	export AWS_REGION="eu-west-2"; \
	sso_session="$$(aws configure get sso_session --profile "$${AWS_PROFILE}")"; \
	aws sso login --sso-session "$${sso_session}"
endef

.PHONY: run
run:
	$(call sso_login); \
	PIPELINE_VISUALISER_SSO_MODE=true \
	ruby index.rb

run_in_docker:
	$(call sso_login); \
	mkdir -p ./docker_aws_config; \
	cp "$${HOME}/.aws/config" ./docker_aws_config/ || { echo "ERROR: AWS config file not found at $${HOME}/.aws/config"; exit 1; }; \
	cp -r "$${HOME}/.aws/sso" ./docker_aws_config/ || { echo "ERROR: AWS SSO cache not found at $${HOME}/.aws/sso"; exit 1; }; \
	docker build -f Dockerfile.local . -t auth-pipeline-visualiser:latest; \
	rm -rf ./docker_aws_config; \
	docker run \
		-p "4567:4567" \
		-e PIPELINE_VISUALISER_SSO_MODE=true \
		-v "$$(pwd):/app" \
		auth-pipeline-visualiser:latest
