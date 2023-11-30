// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {Constants} from "src/base/utils/Constants.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {CAKEDepositor} from "src/cake/depositor/CAKEDepositor.sol";
import {CakeLocker} from "src/cake/locker/CakeLocker.sol";
import {sdToken} from "src/base/token/sdToken.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

contract DeployCakeLLFixed is Script, Test {
    sdToken internal _sdToken;
    CAKEDepositor private depositor;
    ILiquidityGauge internal liquidityGauge;

    CakeLocker private locker = CakeLocker(payable(0x1E6F87A9ddF744aF31157d8DaA1e3025648d042d));

    address public constant GOV = 0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765;
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address public constant VE_CAKE = 0x5692DB8177a81A6c6afc8084C2976C9933EC1bAB;

    address public DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public AIRDROPPER = 0x90569D8A1cF801709577B24dA526118f0C83Fc75;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        // // Deploy sdCAKE
        _sdToken = new sdToken("Stake DAO CAKE", "sdCAKE");
        _sdToken.mint(AIRDROPPER, 727948996702060798269319);

        bytes memory args = abi.encode(address(_sdToken), GOV);

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        deployedAddress = deployBytecode(Constants.LGV4_XCHAIN_BYTECODE, args);

        liquidityGauge = ILiquidityGauge(deployedAddress);

        /// Deploy CAKE Depositor
        depositor = new CAKEDepositor(CAKE, address(locker), address(_sdToken), address(liquidityGauge));
        _sdToken.setOperator(address(depositor));

        vm.stopBroadcast();
    }

    function deployBytecode(bytes memory bytecode, bytes memory args) private returns (address deployed) {
        bytecode = abi.encodePacked(bytecode, args);

        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        require(deployed != address(0), "DEPLOYMENT_FAILED");
    }
}
