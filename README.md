# Stake DAO Contracts Monorepo

```
              ######
      ####################
    ############################
  ##################################
 ######################################
#########################################
######        ##########################
 #####        #########################
  #######   ###############   ## #######
    #####  ############     #### ######
          ###### #####     ##### ######
         ######   #####    #####  #####
        ######    #####    #####   ####
```

## Overview

This repository contains all core smart contracts, libraries, and tools for the Stake DAO protocol. It is organized as a modular monorepo powered by [pnpm workspaces](https://pnpm.io/workspaces).

> For user-facing and protocol documentation, visit [https://docs.stakedao.org/](https://docs.stakedao.org/)

## Packages

The monorepo is organized into several key packages. Each package has its own README with detailed documentation.

> For in-depth details, see the README in each package directory.

- [`lockers/`](./packages/lockers/): Liquid locker protocol (sdToken, veToken, gauges, etc.) for maximizing governance token utility.
- [`strategies/`](./packages/strategies/): Yield aggregator and boosted strategies built on top of sdToken shared boosting.
- [`address-book/`](./packages/address-book/): Canonical registry of all protocol and product contract addresses, with CI-powered exports for off-chain integrations.
- [`shared/`](./packages/shared/): Utility contracts and libraries (e.g., Create3, autovoter, distributors) used by other packages.
- [`interfaces/`](./packages/interfaces/): Shared Solidity interfaces for all protocol integrations, ensuring consistency across packages.

## Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/) (v22+ recommended)
- [pnpm](https://pnpm.io/) (v9+ recommended)
- [Foundry](https://book.getfoundry.sh/) (for Solidity development)
- [Vyper 0.3.10](https://docs.vyperlang.org/en/stable/installing-vyper.html) (required for compiling some gauge contracts in the lockers package)

### Quickstart

1. **Clone the repository:**
   ```sh
   git clone https://github.com/stake-dao/contracts-monorepo.git
   cd contracts-monorepo
   ```
2. **Install dependencies:**
   ```sh
   pnpm install
   ```
3. **Setup environment variables:**
   - Copy `.env.example` to `.env` in each package as needed, and fill in the required keys.

> Each package may have additional setup or requirements described in their respective README files.

## Development Workflow

- **Makefile (optional):**
  The repository includes a Makefile with useful commands for formatting, linting, building, and testing. Example:
  ```sh
  make test
  make lint
  make lint-fix
  ```
- **pnpm workspaces:**
  Use `pnpm` to manage dependencies and scripts across all packages efficiently.

## Documentation & Resources

- **Main documentation:** [https://docs.stakedao.org/](https://docs.stakedao.org/)
- **Deployed contract addresses:** [Stake DAO Offchain Registry](https://github.com/stake-dao/offchain-registry/)

## Contact

For questions, support, or partnership inquiries, please contact: [contact@stakedao.org](mailto:contact@stakedao.org)
