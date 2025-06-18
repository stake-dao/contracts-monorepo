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

test-unit:
	@forge test --match-path "test/unit/**/*.t.sol"

test-integration:
	@forge test --match-path "test/integration/**/*.t.sol" --show-progress --gas-report

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


lint:
	@forge fmt --check && npx solhint "{script,src,test}/**/*.sol"

lint-fix:
	@forge fmt && npx solhint --fix "{script,src,test}/**/*.sol" --fix --noPrompt --disc

# TODO: Remove this once we have a proper simulation framework.
run:
	@forge script script/curve/DeployFraxtal.s.sol -vvvv --broadcast --private-key ${PRIVATE_KEY} --non-interactive

# TODO: Add the verification for the Fraxtal deployment.
verify:
	@npx catapulta-verify --broadcastPath "broadcast/DeployFraxtal.s.sol/11155111/run-latest.json" --rpcUrl 'https://small-greatest-model.ethereum-sepolia.quiknode.pro/${QUICKNODE_KEY}' --explorerUrl 'https://api-sepolia.etherscan.io/api' --etherscanApiKey ${ETHERSCAN_KEY}


.PHONY: test test-unit test-integration lint lint-fix verify
