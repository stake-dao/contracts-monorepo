// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {AddressBook} from "@addressBook/AddressBook.sol";
import {PendleLocker} from "src/pendle/locker/PendleLocker.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {PendleAccumulator} from "src/pendle/accumulator/PendleAccumulator.sol";

interface IExecute {
    function execute(address to, uint256 value, bytes calldata data) external returns (bool, bytes memory);
}

contract DeployPendleAccumulator is Script, Test {
    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public governance = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    PendleAccumulator public pendleAccumulator;

    address public constant pendleStrategy = 0xA7641acBc1E85A7eD70ea7bCFFB91afb12AD0c54;
    PendleLocker public pendleLocker = PendleLocker(AddressBook.PENDLE_LOCKER);
    ILiquidityGauge public liquidityGauge = ILiquidityGauge(AddressBook.GAUGE_SDPENDLE);

    /// List of pools Pendle Locker voted for and eligible to rewards previous to the block 17621271.
    address public constant POOL_1 = 0x2EC8C498ec997aD963969a2c93Bf7150a1F5b213;
    address public constant POOL_2 = 0x4f30A9D41B80ecC5B94306AB4364951AE3170210;
    address public constant POOL_3 = 0xd1434df1E2Ad0Cb7B3701a751D01981c7Cf2Dd62;
    address public constant POOL_4 = 0x08a152834de126d2ef83D612ff36e4523FD0017F;
    address public constant POOL_5 = 0x7D49E5Adc0EAAD9C027857767638613253eF125f;

    function run() public {
        vm.startBroadcast(deployer);

        // Deploy Accumulator Contract
        pendleAccumulator =
            new PendleAccumulator(address(liquidityGauge), governance, governance, AddressBook.VE_SDT_PENDLE_FEE_PROXY);
        pendleAccumulator.setLocker(address(pendleLocker));

        // Add Reward to LGV4
        liquidityGauge.add_reward(AddressBook.WETH, address(pendleAccumulator));

        IExecute(pendleStrategy).execute(
            address(pendleLocker),
            0,
            abi.encodeWithSelector(pendleLocker.setAccumulator.selector, address(pendleAccumulator))
        );

        // Notify Pools
        address[] memory pools = new address[](5);
        pools[0] = POOL_1;
        pools[1] = POOL_2;
        pools[2] = POOL_3;
        pools[3] = POOL_4;
        pools[4] = POOL_5;

        pendleAccumulator.setDistributeAllRewards(true);
        pendleAccumulator.claimAndNotifyAll(pools);
        pendleAccumulator.setDistributeAllRewards(false);

        vm.stopBroadcast();
    }
}
