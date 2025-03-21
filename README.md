# Stake DAO Contracts Monorepo

This repository contains the smart contracts and related packages for the Stake DAO protocol. It is organized as a monorepo using pnpm workspace.

## Repository Structure

The repository is organized into several key packages:

- `address-book/`: Contains contract addresses for different networks
- `autovoter/`: Implementation of automated voting mechanisms
- `herdaddy/`: Tools and contracts for liquidity management
- `interfaces/`: Shared interfaces of all the integrations of StakeDAO used across different packages
- `lockers/`: Smart contracts for sdToken Wrapping mechanisms.
- `safe-modules/`: Gnosis Safe modules and integrations
- `strategies/`: Smart contracts for boosted strategies built on top of sdToken shared boosting.
- `vyper/`: Vyper contract implementations


## TODO:

* Update how address-book is built, the {chainID}.sol format is not ideal.
* Merge auto-voter inside locker as it shares the same context.
* Delete Herdaddy, or Rename it Utility with the goal of having standalone contract useful for a purpose such as Merkle Distribution etc.
* Clean Lockers with Standardized code accross integration (like Strategies)
* Remove the vyper, now that Vyper is supported by Foundry, we can move it back to Lockers