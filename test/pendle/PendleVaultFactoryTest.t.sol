// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

//import "forge-std/Vm.sol";
import "forge-std/Test.sol";
//import "forge-std/console.sol";

import {PendleVaultFactory} from "src/pendle/factory/PendleVaultFactory.sol";
import {PendleStrategy} from "src/pendle/strategy/PendleStrategy.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

interface ILGauge {
    function claimer() external view returns (address);
}

contract PendleVaultFactoryTest is Test {
    PendleVaultFactory internal factory;

    address public constant SDT_DISTRIBUTOR = 0x9C99dffC1De1AfF7E7C1F36fCdD49063A281e18C;
    address public constant PENDLE_LPT = 0xcB71c2A73fd7588E1599DF90b88de2316585A860;
    address public constant CLAIM_REWARDS = 0x633120100e108F03aCe79d6C78Aac9a56db1be0F; // v2
    PendleStrategy public constant PENDLE_STRATEGY = PendleStrategy(0xA7641acBc1E85A7eD70ea7bCFFB91afb12AD0c54);

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);
        factory = new PendleVaultFactory(address(PENDLE_STRATEGY), SDT_DISTRIBUTOR);
        vm.prank(PENDLE_STRATEGY.governance());
        PENDLE_STRATEGY.setVaultGaugeFactory(address(factory));
    }

    function testVaultCreation() public {
        vm.recordLogs();
        factory.cloneAndInit(PENDLE_LPT);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        (address vault,,) = abi.decode(entries[0].data, (address, address, address));
        (address gauge,,) = abi.decode(entries[2].data, (address, address, address));
        assertEq(ERC20Upgradeable(vault).name(), "Stake DAO LPT fUSDC 26DEC2024 Vault");
        assertEq(ERC20Upgradeable(vault).symbol(), "sdLPT fUSDC 26DEC2024-vault");
        assertEq(ERC20Upgradeable(gauge).name(), "Stake DAO LPT fUSDC 26DEC2024 Gauge");
        assertEq(ERC20Upgradeable(gauge).symbol(), "sdLPT fUSDC 26DEC2024-gauge");
        assertEq(ILGauge(gauge).claimer(), CLAIM_REWARDS);
    }
}
