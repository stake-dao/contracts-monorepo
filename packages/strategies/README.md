## Testing

This repository follows the **Branching Tree Technique (BTT)** for structuring test specifications. This methodology enhances clarity and coverage by modeling test cases as branching decision trees.

### Branching Tree Technique

The test specifications are structured using BTT, as outlined in the following references:

- [Paul R. Berg's Introduction to BTT](https://x.com/PaulRBerg/status/1682346315806539776)
- [BTT Overview by Shubhchain](https://shubhchain.hashnode.dev/smart-contract-testing-made-easy)
- [Example BTT Implementations](https://github.com/PaulRBerg/btt-examples)

### Generating Tests with Bulloak

We highly recommend using [Bulloak](https://github.com/alexfertel/bulloak) to generate test files from BTT specifications automatically.

To scaffold test files from your branching tree specification, run:

```sh
bulloak scaffold -w <file_name>.tree
```

### Ensuring Consistency in CI

To pass the CI pipeline, the Solidity files in this package must align with the defined test specifications. You can verify this compliance using:

```sh
bulloak check
```

This ensures that test definitions remain consistent with the implemented smart contract logic.
