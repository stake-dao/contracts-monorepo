-include .env

.EXPORT_ALL_VARIABLES:
MAKEFLAGS += --no-print-directory
RPC_URL=$(RPC_URL_MAINNET)
ETHERSCAN_API_KEY=$(ETHERSCAN_KEY)

default:
	forge fmt && forge build

# Always keep Forge up to date
install:
	foundryup
	forge install

test:
	@forge test

test-f-%:
	@FOUNDRY_MATCH_TEST=$* make test

test-c-%:
	@FOUNDRY_MATCH_CONTRACT=$* make test

test-%:
	@FOUNDRY_TEST=test/$* make test

# Flexible rule for simulation
simulate-%:
	@echo "Target: $@"
	@echo "Match: $*"
	@dirs=$$(echo $* | tr '-' '/'); \
	script_path="script/$$dirs/Deploy.s.sol"; \
	echo "Attempting to simulate: $$script_path"; \
	if [ -f "$$script_path" ]; then \
		forge script "$$script_path:Deploy" -vvvvv --fork-url $(RPC_URL); \
	else \
		echo "Error: $$script_path does not exist"; \
		exit 1; \
	fi

# Flexible rule for simulation
deploy-%:
	@echo "Target: $@"
	@echo "Match: $*"
	@dirs=$$(echo $* | tr '-' '/'); \
	script_path="script/$$dirs/Deploy.s.sol"; \
	echo "Attempting to deploy: $$script_path"; \
	if [ -f "$$script_path" ]; then \
		forge script "$$script_path:Deploy" --broadcast --slow -vvvvv --private-key $(PRIVATE_KEY) --fork-url $(RPC_URL) --verify; \
	else \
		echo "Error: $$script_path does not exist"; \
		exit 1; \
	fi

.PHONY: test coverage