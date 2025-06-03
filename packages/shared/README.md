# Stake DAO Shared

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
        ######    #####    #####   #### Shared
```

## Overview

This package provides a set of utility contracts and libraries used by all major Stake DAO packages. It includes reusable logic for contract deployment (e.g., `Create3`), autovoter mechanisms, and reward distributors.

## Contributing

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
