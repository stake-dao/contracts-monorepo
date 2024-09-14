#!/bin/bash

# Run the TypeScript script and capture the output
output=$(npx ts-node test/common/typescript/getMerkle.ts "$@")

# Print the output
echo "$output"