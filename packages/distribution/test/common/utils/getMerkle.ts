import { MerkleTree } from "merkletreejs";
import { utils, BigNumber } from "ethers";
import keccak256 from "keccak256";
import fs from "fs";
import path from "path";

interface UserReward {
  address: string;
  amount: string;
}

interface MerkleLeaf {
  amount: BigNumber;
  proof: string[];
}

interface RawMerkle {
  merkle: { [address: string]: MerkleLeaf };
  root: string;
  total: BigNumber;
}

function generateMerkle(
  userRewards: UserReward[],
  prevMerkle?: RawMerkle
): RawMerkle {
  const adjustedUserRewards: { [address: string]: BigNumber } = {};

  // Process user rewards and add previous unclaimed rewards
  userRewards.forEach(({ address, amount }) => {
    const lowercaseAddress = address.toLowerCase();
    const reward = utils.parseEther(amount);
    adjustedUserRewards[lowercaseAddress] = (
      adjustedUserRewards[lowercaseAddress] || BigNumber.from(0)
    ).add(reward);
  });

  if (prevMerkle) {
    Object.entries(prevMerkle.merkle).forEach(([address, leaf]) => {
      const lowercaseAddress = address.toLowerCase();
      if (!adjustedUserRewards[lowercaseAddress]) {
        adjustedUserRewards[lowercaseAddress] = leaf.amount;
      } else {
        adjustedUserRewards[lowercaseAddress] = adjustedUserRewards[
          lowercaseAddress
        ].add(leaf.amount);
      }
    });
  }

  const elements: string[] = [];
  const merkle: { [address: string]: MerkleLeaf } = {};
  let totalAmount = BigNumber.from(0);

  Object.entries(adjustedUserRewards).forEach(([address, amount]) => {
    totalAmount = totalAmount.add(amount);
    const leaf = utils.solidityKeccak256(
      ["address", "uint256"],
      [address.toLowerCase(), BigInt(BigNumber.from(amount).toString())]
    );
    elements.push(leaf);
  });

  const merkleTree = new MerkleTree(elements, keccak256, { sort: true });

  Object.entries(adjustedUserRewards).forEach(([address, amount], index) => {
    const leaf = utils.solidityKeccak256(
      ["address", "uint256"],
      [address, amount]
    );
    const proof = merkleTree.getHexProof(leaf);

    // Verify the proof
    const isValid = merkleTree.verify(proof, leaf, merkleTree.getHexRoot());
    if (!isValid) {
      console.error(`Invalid proof generated for address ${address}`);
    }

    merkle[address] = {
      amount,
      proof: merkleTree.getHexProof(elements[index]),
    };
  });

  console.log(totalAmount.toString());

  return {
    merkle,
    root: merkleTree.getHexRoot(),
    total: totalAmount,
  };
}

const args = process.argv.slice(2);
if (args[0] !== "generate" || args.length % 2 !== 1) {
  console.error(
    "Usage: npx ts-node getMerkle.ts generate <address1> <amount1> <address2> <amount2> ..."
  );
  process.exit(1);
}

const userRewards: UserReward[] = [];
for (let i = 1; i < args.length; i += 2) {
  userRewards.push({
    address: args[i],
    amount: args[i + 1],
  });
}

const result = generateMerkle(userRewards);

// Verify all proofs
const elements = Object.entries(result.merkle).map(([address, { amount }]) =>
  utils.solidityKeccak256(["address", "uint256"], [address, amount])
);

Object.entries(result.merkle).forEach(([address, { amount, proof }]) => {
  const leaf = utils.solidityKeccak256(
    ["address", "uint256"],
    [address, amount]
  );

  console.log("Address:", address);
  console.log("Amount:", amount.toString());
  console.log("Leaf:", leaf);
  console.log("Proof:", proof);

  const isValid = new MerkleTree(elements, keccak256, { sort: true }).verify(
    proof,
    leaf,
    result.root
  );
  console.log(
    `Proof verification for ${address}: ${isValid ? "Valid" : "Invalid"}`
  );
});

// Write the result to a JSON file
const outputPath = path.join(__dirname, "data", "merkle_output.json");
fs.writeFileSync(outputPath, JSON.stringify(result, null, 2));

console.log(`Merkle tree data written to ${outputPath}`);
