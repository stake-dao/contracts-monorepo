# Stake DAO Lockers v4

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
        ######    #####    #####   #### Lockers v4
```

[![Unit Tests](https://github.com/stake-dao/contracts-monorepo/actions/workflows/lockers_unit-tests.yml/badge.svg?branch=main)](https://github.com/stake-dao/contracts-monorepo/actions/workflows/lockers_unit-tests.yml)
[![Coverage](https://github.com/stake-dao/contracts-monorepo/actions/workflows/lockers_coverage.yml/badge.svg?branch=main)](https://github.com/stake-dao/contracts-monorepo/actions/workflows/lockers_coverage.yml)
[![Docs](https://github.com/stake-dao/contracts-monorepo/actions/workflows/lockers_docs.yml/badge.svg?branch=main)](https://github.com/stake-dao/contracts-monorepo/actions/workflows/lockers_docs.yml)

## Overview

Stake DAO Lockers v4 are the latest evolution of Stake DAO's liquid locker infrastructure, unlocking the full power of governance tokens for users and protocols. With Lockers, users no longer have to choose between yield, governance, bribes, or liquidity; they get all benefits simultaneously. By integrating with the ve-tokenomics of leading DeFi protocols (Curve, Pendle, Yearn, Balancer, Spectra, FXS, Zero, and more), Stake DAO Lockers provide a permissionless, protocol-agnostic, and cross-chain solution for maximizing utility and flexibility. The protocol is fully governed by the Stake DAO community, ensuring decentralization and continuous improvement.

- **Product page:** [https://www.stakedao.org/lockers](https://www.stakedao.org/lockers)
- **User documentation:** [https://docs.stakedao.org/liquidlockers](https://docs.stakedao.org/liquidlockers) [WIP 🚧]

For a detailed analysis of all contracts, their responsibilities, and how the system works, please refer to the [SPEC.md](./documentation/SPEC.md) file. It contains in-depth documentation of the protocol architecture, component interactions, and process flows.

## Key Features

- **No trade-offs:** Users receive yield, bribes, governance rights, and liquidity simultaneously—no need to compromise.
- **sdTOKENs:** Liquid, tradable tokens representing locked assets. sdTOKENs can be staked, used for governance, or instantly exited via Curve Factory Pools.
- **Perpetual relocking:** Underlying assets are perpetually relocked for maximum rewards, with no manual intervention required.
- **Exit liquidity:** Users can exit their position at any time, ensuring flexibility and capital efficiency.
- **Boosted voting & bribes:** Integration with veSDT enables boosted voting power, and users can participate in bribe markets to monetize their governance rights.
- **veToken Integration:** Seamless interaction with ve-tokenomics of major DeFi protocols.
- **Modular Architecture:** Each integration (Curve, Pendle, etc.) has its own Locker, Accumulator, Depositor, Gauge, sd/ve-Token contracts.
- **SAFE-based Security:** v4 lockers are deployed as Safe accounts, with authorized modules for maintainability and security.
- **Upgradeable & Composable:** Accumulators and depositors are Safe modules, enabling flexible upgrades and permission management.
- **Legacy Support:** Existing pre-v4 lockers remain compatible via a gateway contract. The gateway is a Safe account.
- **Reward Optimization:** Accumulators claim and distribute rewards efficiently, supporting both instant and time-dripped models.
- **Pre-Launch Support:** Special contracts for secure sdToken minting prior to the full deployment of the protocol.
- **On-chain Voting:** Dedicated contracts for protocol and gauge voting, supporting advanced governance workflows.
- **Permissionless & DAO-governed:** The entire system is fully on-chain, upgradable, and governed by the Stake DAO community.
- **Protocol-agnostic & cross-chain:** Designed to be easily extended to new protocols and chains, ensuring long-term scalability and composability.

## Architecture

Stake DAO Lockers v4 introduce a modular, protocol-agnostic architecture. Each protocol integration is found in [`src/integrations/`](./src/integrations/), and includes:

- **Locker:** Locks tokens and receives veTokens from the underlying protocol.
- **Accumulator:** Claims and manages rewards for the locker.
- **Depositor:** Handles deposits, locks tokens, and mints sdTokens.
- **Gauge:** Curve-like gauge for Stake DAO governance and reward distribution.
- **sdToken/veToken:** ERC20 contracts representing staked and voting power.

> For the up-to-date list of integrated protocols, see the [`src/integrations/`](./src/integrations/) directory.

### SAFE Modules & Gateway Pattern

- **Future Lockers:** Deployed as Safe accounts. Accumulators and depositors are pre-authorized Safe modules, able to act on behalf of the Safe (locker) for secure, transparent, and permissioned operations.
- **Legacy Lockers:** Remain as standard contracts. A gateway Safe contract is introduced between modules and the locker, acting as a middleman responsible for operating the locker.
- **Implementation:** The gateway/locker logic is implemented in [`SafeModule.sol`](./src/utils/SafeModule.sol), inherited by all accumulators and depositors.

## Utilities & Variants

- **AccumulatorDripping:** Extension of the Accumulator for distributing ERC20 rewards over a fixed period (used by Pendle).
- **AccumulatorDelegable:** Extension of the Accumulator for delegated reward distribution (used by Curve/Balancer).
- **LockerPreLaunch:** Enables secure sdToken minting prior to the full deployment of the protocol (used by Yieldnest).
- **DepositorPreLaunch:** Pre-launch variant of the depositor contract, replaced by the definitive version at protocol launch.

## Voting

This package also provides robust on-chain voting infrastructure for all integrated protocols:

- **VoteGaugeRouter:** Unified entry point for voting on gauges across multiple protocols.
- **VoterBase & VoterPermissionManager:** Abstract and permission management contracts for voting logic.
- **Protocol-specific Voters:** Each protocol has its own voter contract (e.g., `CurveVoter.sol`, `BalancerVoter.sol`, `PendleVoter.sol`) for on-chain and gauge voting.

## Documentation & Resources

- **User documentation:** [https://docs.stakedao.org/liquidlockers](https://docs.stakedao.org/liquidlockers)
- **Deployed contracts:** [Stake DAO Offchain Registry](https://github.com/stake-dao/offchain-registry/)

## Contributing

> **Note:** Before running or testing the project, you must create a `.env` file in the root of this package and populate it with the required keys from the `.env.example` file. This is necessary for local development and CI to work correctly.

> **Vyper Requirement:** This project uses Solidity for its contracts. However, the gauge contracts inherit from Curve's implementation, which is written in Vyper. To compile all the contracts, you need **Vyper 0.3.10** installed locally. Please ensure you have this version before contributing. For installation instructions, refer to the [official Vyper documentation](https://docs.vyperlang.org/en/stable/installing-vyper.html).

This package is a Foundry-based smart contract project and targets Solidity version `0.8.28`.

### Setup

To install all dependencies for this package, run the following command at the root of the repository:

```sh
pnpm install
```

### Quality

We enforce consistent code style and quality using the following tools:

- **Formatting:** [Forge fmt](https://book.getfoundry.sh/forge/formatting) is used to automatically format Solidity code.
- **Linting:** [solhint](https://github.com/protofire/solhint) is used to lint Solidity code for style and best practices.

To check code formatting and linting, run:

```sh
make lint
```

To automatically fix formatting and linting issues, run:

```sh
make lint-fix
```

Please ensure your code passes these checks before submitting a pull request.

### Testing

We use the **Branching Tree Technique (BTT)** to structure test specifications, which enhances clarity and coverage by modeling test cases as branching decision trees.

#### Branching Tree Technique

Test specifications are written using BTT. For more information, see:

- [Paul R. Berg's Introduction to BTT](https://x.com/PaulRBerg/status/1682346315806539776)
- [BTT Overview by Shubhchain](https://shubhchain.hashnode.dev/smart-contract-testing-made-easy)
- [Example BTT Implementations](https://github.com/PaulRBerg/btt-examples)

#### Generating Tests with Bulloak

We recommend using [Bulloak](https://github.com/alexfertel/bulloak) to generate test files from BTT specifications automatically.

To scaffold test files from your branching tree specification, run:

```sh
bulloak scaffold -w <file_name>.tree -s 0.8.28
```

## License

This package is licensed under the Business Source License (BSL). See the LICENSE file for details. The BSL expires on **January 1, 2028** or as set on-chain.

## Contact

For questions, support, or partnership inquiries, please contact: [contact@stakedao.org](mailto:contact@stakedao.org)
