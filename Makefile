# ==============================================================================
# QuipToken Makefile
# ==============================================================================
# Load .env if present and export every key so forge's vm.env* sees them.
# Keep FOUNDRY_PROFILE OUT of .env — the deploy targets set it inline.
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# RPC indirection: RPC=API_URL_BASE_SEPOLIA uses the value of $(API_URL_BASE_SEPOLIA)
RPC_URL = $($(RPC))

# ==============================================================================
# Development
# ==============================================================================

.PHONY: install
install: ## Install dependencies (bun for LayerZero/OZ, soldeer for forge-std/solady)
	bun install
	forge soldeer install

.PHONY: build
build: ## Build contracts
	forge build

.PHONY: test
test: ## Run all tests (fork tests self-skip without API_URL_BASE_SEPOLIA)
	forge test

.PHONY: test-v
test-v: ## Run tests with verbosity
	forge test -vvv

.PHONY: test-fork
# The only tests that execute the REAL CreateX bytecode and LayerZero endpoint.
test-fork: ## Validate the CreateX guard and a real deploy against Base Sepolia (needs API_URL_BASE_SEPOLIA)
	forge test --match-contract Constants_CreateXFork -vv

.PHONY: build-prod
build-prod: ## Build the deployment artifact with the prod profile (out-prod/, metadata stripped)
	FOUNDRY_PROFILE=prod forge build --sizes

.PHONY: fmt
fmt: ## Format code
	forge fmt

.PHONY: fmt-check
fmt-check: ## Check formatting
	forge fmt --check

.PHONY: clean
clean: ## Clean build artifacts
	forge clean

# ==============================================================================
# Deployment (canonical CreateX factory, CREATE3, permissioned salt)
#
# The deployer EOA is COMPILED IN as Constants.DEPLOYER: the CreateX salt is
# permissioned to it, so it is part of the address. DEPLOYER_PK must derive it.
#
# Before ANY broadcast, run the free gates:
#   make test-fork                        guard + deploy against live CreateX
#   make deploy-dry RPC=... SCRIPT=...    must print the expected address
#   make deploy-dry-wrong-signer RPC=...  must FAIL (proves the signer gate)
#
# Deploy the home chain first (it mints the supply), then every remote chain in
# the family, then wire peers between all of them from the delegate.
# ==============================================================================

FOUNDRY_PROD := FOUNDRY_PROFILE=prod

# Default to the testnet family; pass SCRIPT=DeployMainnet for mainnets.
SCRIPT ?= DeployTestnet

# Anvil account #0 — a PUBLIC key used only to prove the signer gate rejects it.
WRONG_PK := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

.PHONY: anvil-fork
anvil-fork: ## Start Anvil forking a chain with CreateX. Usage: make anvil-fork RPC=API_URL_BASE_SEPOLIA
	anvil --fork-url $(RPC_URL)

.PHONY: deploy-dry
deploy-dry: ## Dry run (no broadcast; runs every gate). Usage: make deploy-dry RPC=API_URL_SEPOLIA [SCRIPT=DeployMainnet]
	@$(FOUNDRY_PROD) forge script script/$(SCRIPT).s.sol \
		--rpc-url $(RPC_URL) \
		--private-key $(DEPLOYER_PK)

.PHONY: deploy
deploy: ## Deploy + broadcast + verify. Usage: make deploy RPC=API_URL_SEPOLIA [SCRIPT=DeployMainnet]
	@$(FOUNDRY_PROD) forge script script/$(SCRIPT).s.sol \
		--rpc-url $(RPC_URL) \
		--private-key $(DEPLOYER_PK) \
		--broadcast \
		--verify

.PHONY: deploy-dry-wrong-signer
deploy-dry-wrong-signer: ## Prove the signer gate works: this MUST fail. Usage: make deploy-dry-wrong-signer RPC=API_URL_BASE_SEPOLIA
	@echo 'Rehearsing with a public dev key - this MUST fail...'
	@if $(FOUNDRY_PROD) DEPLOYER_PK=$(WRONG_PK) QUIP_TOKEN_DELEGATE=0x0000000000000000000000000000000000000001 \
		forge script script/$(SCRIPT).s.sol --rpc-url $(RPC_URL) --private-key $(WRONG_PK) >/dev/null 2>&1; then \
		echo 'FAIL: the deploy script ACCEPTED a non-ops signer'; exit 1; \
	else \
		echo 'OK: the deploy script rejected a non-ops signer'; \
	fi

# ── Per-chain targets (foundry.toml [rpc_endpoints] aliases). EXPECTED_CHAIN_ID
#    is pinned inline so a mistyped alias aborts before broadcasting.
.PHONY: deploy-sepolia
deploy-sepolia: ## Deploy to Sepolia (testnet HOME chain: mints the supply)
	@$(FOUNDRY_PROD) EXPECTED_CHAIN_ID=11155111 forge script script/DeployTestnet.s.sol \
		--rpc-url sepolia --private-key $(DEPLOYER_PK) --broadcast --verify

.PHONY: deploy-base-sepolia
deploy-base-sepolia: ## Deploy to Base Sepolia (testnet remote chain)
	@$(FOUNDRY_PROD) EXPECTED_CHAIN_ID=84532 forge script script/DeployTestnet.s.sol \
		--rpc-url base_sepolia --private-key $(DEPLOYER_PK) --broadcast --verify

.PHONY: deploy-mainnet
deploy-mainnet: ## Deploy to Ethereum MAINNET (HOME chain: mints the supply). Run every gate first.
	@$(FOUNDRY_PROD) EXPECTED_CHAIN_ID=1 forge script script/DeployMainnet.s.sol \
		--rpc-url mainnet --private-key $(DEPLOYER_PK) --broadcast --verify

.PHONY: deploy-base
deploy-base: ## Deploy to Base MAINNET (remote chain). Run every gate first.
	@$(FOUNDRY_PROD) EXPECTED_CHAIN_ID=8453 forge script script/DeployMainnet.s.sol \
		--rpc-url base --private-key $(DEPLOYER_PK) --broadcast --verify

# ==============================================================================
# Wiring (peers, pinned ULN302 libraries, 2-of-2 DVNs, executor, enforced gas)
#
# Run on EVERY chain once the whole family is deployed. Without DELEGATE_PK it
# only prints the planned calls (target + calldata) for the delegate multisig;
# re-running after they execute must report "Planned calls: 0".
# ==============================================================================

.PHONY: wire
wire: ## Print the wiring plan for one chain. Usage: make wire RPC=API_URL_SEPOLIA
	forge script script/WireQuipToken.s.sol --rpc-url $(RPC_URL)

.PHONY: wire-broadcast
wire-broadcast: ## Execute the wiring plan with DELEGATE_PK (owner AND endpoint delegate). Usage: make wire-broadcast RPC=API_URL_SEPOLIA
	@forge script script/WireQuipToken.s.sol --rpc-url $(RPC_URL) --private-key $(DELEGATE_PK) --broadcast

.PHONY: test-fork-all
test-fork-all: ## Run every fork test (CreateX deploy + wiring) against Base Sepolia
	forge test --match-path 'test/**/integration/*' -vv

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-26s %s\n", $$1, $$2}'
