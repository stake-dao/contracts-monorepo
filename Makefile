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

simulate-%:
	make default
	@echo "Target: $@"
	@echo "Match: $*"
	@dirs=$$(echo $* | tr '-' '/'); \
	script_path="script/$$dirs.s.sol"; \
	if [ -f "$$script_path" ]; then \
		contract_name=$$(basename "$$dirs"); \
		echo "Attempting to simulate: $$script_path:$$contract_name"; \
		forge script "$$script_path:$$contract_name" -vvvvv; \
	else \
		script_path="script/$$dirs/Deploy.s.sol"; \
		echo "Attempting to simulate (fallback): $$script_path"; \
		if [ -f "$$script_path" ]; then \
			forge script "$$script_path:Deploy" -vvvvv; \
		else \
			echo "Error: Neither $$dirs.s.sol nor $$dirs/Deploy.s.sol exists"; \
			exit 1; \
		fi; \
	fi

deploy-%:
	@echo "Target: $@"
	@echo "Match: $*"
	@dirs=$$(echo $* | tr '-' '/'); \
	script_path="script/$$dirs.s.sol"; \
	script_name=""; \
	if [ -f "$$script_path" ]; then \
		contract_name=$$(basename "$$dirs"); \
		script_name="$$contract_name.s.sol"; \
		echo "Attempting to deploy: $$script_path:$$contract_name"; \
		forge script "$$script_path:$$contract_name" --broadcast --slow -vvvvv --private-key $(PRIVATE_KEY) --verify --etherscan-api-key $(ETHERSCAN_KEY) $(DEPLOY_ARGS); \
		deployment_success=$$?; \
	else \
		script_path="script/$$dirs/Deploy.s.sol"; \
		script_name="Deploy.s.sol"; \
		echo "Attempting to deploy (fallback): $$script_path"; \
		if [ -f "$$script_path" ]; then \
			forge script "$$script_path:Deploy" --broadcast --slow -vvvvv --private-key $(PRIVATE_KEY) --verify --etherscan-api-key $(ETHERSCAN_KEY) $(DEPLOY_ARGS); \
			deployment_success=$$?; \
		else \
			echo "Error: Neither $$dirs.s.sol nor $$dirs/Deploy.s.sol exists"; \
			exit 1; \
		fi; \
	fi; \
	if [ $$deployment_success -eq 0 ]; then \
		echo "Deployment successful!"; \
		if [ -n "$(SKIP_VERIFY)" ]; then \
			echo "Skipping verification as requested"; \
		elif [ -f "packages/strategies/script/utils/UniversalVerify.s.sol" ]; then \
			echo "Waiting for contract to be indexed..."; \
			sleep 30; \
			if [ -n "$(MULTI_CHAIN)" ]; then \
				echo "Running multi-chain verification..."; \
				cd packages/strategies && forge script script/utils/UniversalVerify.s.sol:UniversalVerify --sig "verifyFromBroadcastMultiChain(string)" "$$script_path" --ffi; \
			else \
				chain=$$(echo $* | cut -d'-' -f1); \
				if [ -n "$$chain" ] && [ "$$chain" != "$*" ]; then \
					echo "Running single-chain verification for $$chain..."; \
					cd packages/strategies && forge script script/utils/UniversalVerify.s.sol:UniversalVerify --sig "verifyFromBroadcast(string,string)" "$$script_path" "$$chain" --ffi; \
				else \
					echo "Chain not specified, skipping auto-verification"; \
				fi; \
			fi; \
		else \
			echo "UniversalVerify script not found, skipping auto-verification"; \
		fi; \
	else \
		echo "Deployment failed, skipping verification"; \
		exit $$deployment_success; \
	fi

verify-script-%:
	@echo "Verifying from script: $*"
	@chain=""; \
	remaining="$*"; \
	for c in mainnet arbitrum optimism base polygon; do \
		if echo "$$remaining" | grep -q "-$$c$$"; then \
			chain="$$c"; \
			remaining=$$(echo "$$remaining" | sed "s/-$$c$$//"); \
			break; \
		fi; \
	done; \
	script_file=$$(echo "$$remaining" | tr '-' '/'); \
	script_path="script/$$script_file.s.sol"; \
	if [ -n "$$chain" ]; then \
		echo "Chain: $$chain"; \
		echo "Script: $$script_path"; \
		cd packages/strategies && forge script script/utils/UniversalVerify.s.sol:UniversalVerify --sig "verifyFromBroadcast(string,string)" "$$script_path" "$$chain" --ffi; \
	else \
		echo "Multi-chain verification"; \
		echo "Script: $$script_path"; \
		cd packages/strategies && forge script script/utils/UniversalVerify.s.sol:UniversalVerify --sig "verifyFromBroadcastMultiChain(string)" "$$script_path" --ffi; \
	fi

verify-direct-%:
	@echo "Direct contract verification: $*"
	@# Parse: address-contractPath[-chain]
	@# Example: 0x123...-src/Contract.sol:Contract-mainnet
	@address=$$(echo "$*" | cut -d'-' -f1); \
	remaining=$$(echo "$*" | cut -d'-' -f2-); \
	chain=""; \
	for c in mainnet arbitrum optimism base polygon; do \
		if echo "$$remaining" | grep -q "-$$c$$"; then \
			chain="$$c"; \
			remaining=$$(echo "$$remaining" | sed "s/-$$c$$//"); \
			break; \
		fi; \
	done; \
	contract_path=$$(echo "$$remaining" | tr '-' '/'); \
	if [ -n "$$chain" ]; then \
		echo "Address: $$address"; \
		echo "Contract: $$contract_path"; \
		echo "Chain: $$chain"; \
		cd packages/strategies && forge script script/utils/UniversalVerify.s.sol:UniversalVerify --sig "verifyDirect(address,string,string)" "$$address" "$$contract_path" "$$chain" --ffi; \
	else \
		echo "Address: $$address"; \
		echo "Contract: $$contract_path"; \
		echo "Multi-chain verification"; \
		cd packages/strategies && forge script script/utils/UniversalVerify.s.sol:UniversalVerify --sig "verifyDirectMultiChain(address,string)" "$$address" "$$contract_path" --ffi; \
	fi

verify-%:
	@echo "Target: $@"
	@echo "Match: $*"
	@if echo "$*" | grep -q "^[^-]*-0x[0-9a-fA-F]*-"; then \
		chain=$$(echo "$*" | cut -d'-' -f1); \
		address=$$(echo "$*" | cut -d'-' -f2); \
		contract_info=$$(echo "$*" | cut -d'-' -f3-); \
		contract_name=$$(echo "$$contract_info" | cut -d'-' -f1); \
		source_path=$$(echo "$$contract_info" | cut -d'-' -f2- | tr '-' '/'); \
		echo "Verifying contract: $$contract_name at $$address on $$chain"; \
		echo "Source path: src/$$source_path.sol"; \
		forge script script/utils/VerifyContract.s.sol:VerifyContract --sig "verifyContract(string,address,string,string)" "$$chain" "$$address" "$$contract_name" "src/$$source_path.sol" --ffi; \
	else \
		echo "Usage: make verify-CHAIN-ADDRESS-CONTRACT_NAME-SOURCE_PATH"; \
		echo "Example: make verify-mainnet-0x123...-UniversalBoostRegistry-merkl/UniversalBoostRegistry"; \
		exit 1; \
	fi

verify-multi-%:
	@echo "Target: $@"
	@echo "Match: $*"
	@address=$$(echo "$*" | cut -d'-' -f1); \
	contract_info=$$(echo "$*" | cut -d'-' -f2-); \
	contract_name=$$(echo "$$contract_info" | cut -d'-' -f1); \
	source_path=$$(echo "$$contract_info" | cut -d'-' -f2- | tr '-' '/'); \
	echo "Multi-chain verification for: $$contract_name at $$address"; \
	echo "Source path: src/$$source_path.sol"; \
	if [ "$$contract_name" = "UniversalBoostRegistry" ]; then \
		forge script script/utils/VerifyContract.s.sol:VerifyContract --sig "verifyUniversalBoostRegistry(address)" "$$address" --ffi; \
	else \
		echo "Multi-chain verification not configured for $$contract_name"; \
		echo "Use individual chain verification instead"; \
		exit 1; \
	fi

.PHONY: test test-unit test-integration lint lint-fix verify-script-% verify-direct-% verify-% verify-multi-%
