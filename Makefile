include .env

.EXPORT_ALL_VARIABLES:
MAKEFLAGS += --no-print-directory

default:
	@forge fmt && forge build

clean:
	@forge clean && make default

# Always keep Forge up to date
install:
	foundryup
	rm -rf node_modules
	pnpm i

test:
	@forge test

test-f-%:
	@FOUNDRY_MATCH_TEST=$* make test

test-c-%:
	@FOUNDRY_MATCH_CONTRACT=$* make test

test-m-%:
	@network=$$(echo "$*" | cut -d'-' -f1); \
	script_path="test/$$network/"; \
	FOUNDRY_TEST=$$script_path make test; \

test-%:
	@network=$$(echo "$*" | cut -d'-' -f1); \
	project=$$(echo "$*" | cut -d'-' -f2); \
	file=$$(echo "$*" | cut -d'-' -f3-); \
	capitalized_file=$$(echo "$$file" | tr '[:lower:]' '[:upper:]' | cut -c1)$$(echo "$$file" | cut -c2-); \
	script_path="test/$$network/$$project/$$capitalized_file.t.sol"; \
	if [ -f "$$script_path" ]; then \
		echo "Running test: $$script_path"; \
		FOUNDRY_TEST=$$script_path make test; \
	else \
		echo "Test file not found: $$script_path"; \
		exit 1; \
	fi

simulate-%:
	make default
	@echo "Target: $@"
	@echo "Match: $*"
	@dirs=$$(echo $* | tr '-' '/'); \
	script_path="script/$$dirs/Deploy.s.sol"; \
	echo "Attempting to simulate: $$script_path"; \
	if [ -f "$$script_path" ]; then \
		forge script "$$script_path:Deploy" -vvvvv; \
	else \
		echo "Error: $$script_path does not exist"; \
		exit 1; \
	fi

deploy-%:
	@echo "Target: $@"
	@echo "Match: $*"
	@dirs=$$(echo $* | tr '-' '/'); \
	script_path="script/$$dirs/Deploy.s.sol"; \
	echo "Attempting to deploy: $$script_path"; \
	if [ -f "$$script_path" ]; then \
		forge script "$$script_path:Deploy" --broadcast --slow -vvvvv --private-key $(PRIVATE_KEY);\
	else \
		echo "Error: $$script_path does not exist"; \
		exit 1; \
	fi

.PHONY: test