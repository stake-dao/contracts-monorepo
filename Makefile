
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

test-%:
	@echo "Target: $@"
	@echo "Match: $*"
	@dirs=$$(echo $* | tr '-' '/'); \
	script_path="test/$$dirs/"; \
	FOUNDRY_TEST=$$script_path make test

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
		forge script "$$script_path:Deploy" --broadcast --slow -vvvvv --private-key $(PRIVATE_KEY) --verify; \
	else \
		echo "Error: $$script_path does not exist"; \
		exit 1; \
	fi

.PHONY: test