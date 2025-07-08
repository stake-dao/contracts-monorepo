-include .env
-include ../../Makefile

# Strategy-specific deployment targets
simulate-%:
	@network=$$(echo "$*" | tr '[:upper:]' '[:lower:]'); \
	capitalized_network=$$(echo "$$network" | tr '[:lower:]' '[:upper:]' | cut -c1)$$(echo "$$network" | cut -c2-); \
	script_path="script/curve/Deploy$$capitalized_network.s.sol"; \
	rpc_network=$$network; \
	if [ "$$network" = "fraxtal" ]; then rpc_network="frax"; fi; \
	if [ -f "$$script_path" ]; then \
		echo "Simulating deployment to $$network..."; \
		forge script $$script_path:Deploy$$capitalized_network --rpc-url $$rpc_network -vvvv; \
	else \
		echo "Deployment script not found: $$script_path"; \
		echo "Available networks: mainnet, base, fraxtal"; \
		exit 1; \
	fi

deploy-%:
	@network=$$(echo "$*" | tr '[:upper:]' '[:lower:]'); \
	capitalized_network=$$(echo "$$network" | tr '[:lower:]' '[:upper:]' | cut -c1)$$(echo "$$network" | cut -c2-); \
	script_path="script/curve/Deploy$$capitalized_network.s.sol"; \
	rpc_network=$$network; \
	if [ "$$network" = "fraxtal" ]; then rpc_network="frax"; fi; \
	if [ -f "$$script_path" ]; then \
		echo "Deploying to $$network..."; \
		forge script $$script_path:Deploy$$capitalized_network --rpc-url $$rpc_network --broadcast --verify; \
	else \
		echo "Deployment script not found: $$script_path"; \
		echo "Available networks: mainnet, base, fraxtal"; \
		exit 1; \
	fi