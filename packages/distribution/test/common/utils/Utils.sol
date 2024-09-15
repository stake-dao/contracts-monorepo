// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/src/Test.sol";

contract Utils is Test {
    string constant MERKLE_DATA_PATH = "/test/common/utils/data/merkle_output.json";

    function generateMerkleProof(string[] memory userAddresses, string[] memory amounts) internal {
        require(userAddresses.length == amounts.length, "Mismatched input lengths");

        string[] memory inputs = new string[](2 + userAddresses.length * 2);
        inputs[0] = "./test/common/utils/getMerkle.sh";
        inputs[1] = "generate";

        for (uint256 i = 0; i < userAddresses.length; i++) {
            inputs[2 + i * 2] = userAddresses[i];
            inputs[3 + i * 2] = amounts[i];
        }

        vm.ffi(inputs);
    }

    function getMerkleJSONData()
        internal
        view
        returns (address[] memory userAddresses, uint256[] memory amounts, bytes32[][] memory proofs)
    {
        string memory root = vm.projectRoot();
        string memory merklePath = string.concat(root, MERKLE_DATA_PATH);

        string memory json = vm.readFile(merklePath);
        string[] memory users = vm.parseJsonKeys(json, "$.merkle");

        userAddresses = new address[](users.length);
        amounts = new uint256[](users.length);
        proofs = new bytes32[][](users.length);

        for (uint256 i = 0; i < users.length; i++) {
            userAddresses[i] = vm.parseAddress(users[i]);

            // Get the amount
            string memory amountHex = vm.parseJsonString(json, string.concat("$.merkle.", users[i], ".amount.hex"));

            amounts[i] = vm.parseUint(amountHex);

            // Get the proof
            string[] memory proofStrings = vm.parseJsonStringArray(json, string.concat("$.merkle.", users[i], ".proof"));
            proofs[i] = new bytes32[](proofStrings.length);
            for (uint256 j = 0; j < proofStrings.length; j++) {
                proofs[i][j] = vm.parseBytes32(proofStrings[j]);
            }
        }
    }

    function getMerkleRootAndTotal() internal view returns (bytes32 merkleRoot, uint256 total) {
        string memory root = vm.projectRoot();
        string memory merklePath = string.concat(root, MERKLE_DATA_PATH);

        string memory json = vm.readFile(merklePath);

        // Get the merkle root
        string memory rootHex = vm.parseJsonString(json, "$.root");
        merkleRoot = vm.parseBytes32(rootHex);

        // Get the total
        string memory totalHex = vm.parseJsonString(json, "$.total.hex");
        total = vm.parseUint(totalHex);
    }
}
