# Stake DAO Contracts Monorepo

This repository contains the smart contracts and related packages for the Stake DAO protocol. It is organized as a monorepo using pnpm workspace.

## Repository Structure

The repository is organized into several key packages:

- `address-book/`: Contains contract addresses for different networks
- `shared/`: Tools and contracts for shared functionality
- `interfaces/`: Shared interfaces of all the integrations of StakeDAO used across different packages
- `lockers/`: Smart contracts for sdToken Wrapping mechanisms.
- `strategies/`: Smart contracts for boosted strategies built on top of sdToken shared boosting.

## TODO:

- Delete Herdaddy, or Rename it Utility with the goal of having standalone contract useful for a purpose such as Merkle Distribution etc.
- Clean Lockers with Standardized code accross integration (like Strategies)
