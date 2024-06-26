-include .env

.EXPORT_ALL_VARIABLES:
MAKEFLAGS += --no-print-directory
ETHERSCAN_API_KEY=$(API_KEY_ETHERSCAN)
PRIVATE_KEY=$(DEPLOYER_PRIVATE_KEY)
RPC_URL=https://bsc-pokt.nodies.app #https://binance.llamarpc.com

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

coverage:
	@forge coverage --report lcov
	@lcov --ignore-errors unused --remove ./lcov.info -o ./lcov.info.pruned "test/*" "script/*"
	@rm ./lcov.info*

coverage-html:
	@make coverage
	@genhtml ./lcov.info.pruned -o report --branch-coverage --output-dir ./coverage
	@rm ./lcov.info*

simulate-%:
	@forge script script/$*.s.sol  -vvvvv --rpc-url ${RPC_URL}

run-%:
	@forge script script/$*.s.sol --broadcast --slow -vvvvv --private-key $(PRIVATE_KEY) --rpc-url ${RPC_URL} --verify

deploy-%:
	@forge script script/$*.s.sol --broadcast --slow -vvvvv --private-key ${PRIVATE_KEY} --rpc-url ${RPC_URL}

.PHONY: test coverage