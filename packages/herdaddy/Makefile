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

coverage:
	@forge coverage --report lcov
	@lcov --ignore-errors unused --remove ./lcov.info -o ./lcov.info.pruned "test/*" "script/*"
	@rm ./lcov.info*

coverage-html:
	@make coverage
	@genhtml ./lcov.info.pruned -o report --branch-coverage --output-dir ./coverage
	@rm ./lcov.info*

.PHONY: test coverage