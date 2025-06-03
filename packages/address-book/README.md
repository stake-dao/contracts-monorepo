# Stake DAO Address Book

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
        ######    #####    #####   #### Address Book
```

[![Synchronization](https://github.com/stake-dao/contracts-monorepo/actions/workflows/book_synchronization.yml/badge.svg?branch=main)](https://github.com/stake-dao/contracts-monorepo/actions/workflows/book_synchronization.yml)

## Overview

The Stake DAO Address Book is the canonical, up-to-date mapping of all protocol and product smart contract addresses used by Stake DAO and its ecosystem. It serves as the **single source of truth** for addresses referenced by other smart contract packages, scripts, and off-chain integrations.

- **Centralized Address Management:** All protocol, DAO, and product addresses are maintained in one place, ensuring consistency and reducing the risk of errors across the Stake DAO codebase.
- **Automation:** The CI pipeline automatically exports the address book to both JSON and Markdown formats and uploads them to the [Stake DAO Offchain Registry](https://github.com/stake-dao/offchain-registry/tree/main/data/address-book) for use in documentation, monitoring, and integrations.
- **Reference:** Other smart contract packages and off-chain tools should import addresses from here, not hardcode them elsewhere.

## Where to find the address book library files

- All Solidity address book libraries are located in [`src/`](./src/).
- Each file corresponds to a protocol and network, and may contain multiple libraries for different products or sections (e.g., Protocol, Locker, Votemarket).
- Example:
  - `CurveEthereum.sol` — Curve protocol addresses on Ethereum
  - `SpectraBase.sol` — Spectra protocol addresses on Base
  - `DaoEthereum.sol` — DAO addresses on Ethereum

## CI Automation & Outputs

- The CI pipeline automatically generates and uploads:
  - **`address-book.json`** — Machine-readable, hierarchical address book for programmatic use.
  - **`README.md`** — Human-friendly Markdown address book for documentation and review.
- Both files are available in the [Stake DAO Offchain Registry](https://github.com/stake-dao/offchain-registry/tree/main/data/address-book).
- **Do NOT run the scripts manually.** The output files are git-ignored and will be generated automatically by the CI pipeline on every relevant change.

## Scripts

The [`scripts/`](./scripts/) directory contains automation tools for generating address book outputs:

- **`generate-json-book.js`**
  Scans all Solidity files in `src/`, extracts addresses, and outputs a hierarchical, machine-readable `address-book.json`.

  - Handles DAO and Common flattening
  - Resolves `CommonUniversal` references
  - Enforces conventions and reports errors

- **`generate-md-book.js`**
  Converts `address-book.json` into a human-friendly Markdown file (`generated/README.md`).
  - Organizes by protocol, network, and product
  - Flattens DAO and Common sections
  - Adds explorer links for each address
  - Includes an auto-generated warning

**Usage (for reference only):**
Run the scripts sequentially from the package root:

```sh
pnpm run generate-json
pnpm run generate-md
```

## Contributing

To contribute to the address book, please follow these guidelines:

- **Add new addresses** by creating or updating the appropriate file in `src/` following the conventions below.
- **Review your Solidity changes locally.** Generated outputs will be uploaded and distributed by CI for documentation and integration purposes.

### ✅ DOs and ❌ DON'Ts

#### ✅ DOs

- **Follow the filename convention:**
  `ProtocolNetwork.sol` (e.g., `CurveEthereum.sol`, `DaoBsc.sol`, `CommonPolygon.sol`)
- **Use the correct structure:**
  Each file may define one or more Solidity `library` contracts, typically grouped by protocol and product (e.g., `library BalancerProtocol { ... }`, `library BalancerLocker { ... }`).
  The file name should follow the `ProtocolNetwork.sol` convention, but the libraries inside may be named `{Protocol}{Product}` or similar.
- **Declare all addresses as `address internal constant`:**
  ```solidity
  address internal constant TOKEN = 0x...;
  ```
- **Capitalize all address labels:**
  Use uppercase for all label names (e.g., `TOKEN`, `LOCKER`, `GAUGE_CONTROLLER`).
- **Group addresses logically:**
  By protocol, network, and product as appropriate, using separate libraries within the same file if needed.
- **Keep the structure flat for DAO and Common files:**
  No product-level nesting; just a mapping of labels to addresses.
- **Document any special cases or placeholders.**

#### ❌ DON'Ts

- **Don't use non-standard naming or structure:**
  The scripts rely on strict conventions for parsing.
- **Don't use non-constant or non-internal variables:**
  Only `address internal constant` is supported.
- **Don't use lowercase or mixed-case for labels:**
  Always use uppercase.
- **Don't add unrelated logic or functions:**
  These files are for address constants only.
- **Don't duplicate addresses across files unless necessary.**

## Additional Notes

- **This package is the single source of truth for all Stake DAO addresses.**
  All other packages and integrations should reference addresses from here.
- **For questions or issues, open an issue or contact the Stake DAO engineering team.**
