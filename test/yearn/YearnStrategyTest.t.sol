// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/Vm.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "utils/VyperDeployer.sol";

import {AddressBook} from "addressBook/AddressBook.sol";
import {YearnStrategy} from "src/yearn/strategy/YearnStrategy.sol";
import {StrategyVault} from "src/base/vault/StrategyVault.sol";
import {YearnVaultFactory} from "src/yearn/factory/YearnVaultFactory.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface ICurvePool {
    function exchange_underlying(uint256, uint256, uint256, uint256) external payable;
}

interface IDyfiOption {
    function eth_required(uint256) external view returns(uint256);
    function redeem(uint256) external payable;
}

contract YearnStrategyTest is Test {
    YearnVaultFactory public factory;
    YearnStrategy public strategy;
    StrategyVault public vault;
    address public locker;
    address public veToken;
    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address public sdYFI;
    address public sdtDistributor;

    address public constant YEARN_GAUGE_1 = 0x81d93531720d86f0491DeE7D03f30b3b5aC24e59; // yETh
    address public constant YEARN_LP_1 = 0x58900d761Ae3765B75DDFc235c1536B527F25d8F;
    address public constant YEARN_GAUGE_2 = 0x7Fd8Af959B54A677a1D8F92265Bd0714274C56a3; // YFI-ETH
    address public constant YEARN_LP_2 = 0x790a60024bC3aea28385b60480f15a0771f26D09;
    address public constant YEARN_GAUGE_3 = 0x107717C98C8125A94D3d2Cc82b86a1b705f3A27C; // yCRV
    address public constant YEARN_LP_3 = 0x6E9455D109202b426169F0d8f01A3332DAE160f3;

    address public constant DYFIETH_POOL = 0x8aC64Ba8E440cE5c2d08688f4020698b1826152E;
    address public constant DYFI_OPTION = 0x2fBa208E1B2106d40DaA472Cb7AE0c6C7EFc0224;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("ethereum"));
        vm.selectFork(forkId);

        locker = AddressBook.YFI_LOCKER;
        veToken = AddressBook.VE_YFI;
        sdYFI = AddressBook.SD_YFI;
        sdtDistributor = AddressBook.SDT_DISTRIBUTOR_STRAT;

        strategy = new YearnStrategy(address(this), locker, veToken, DYFI, sdYFI);

        factory = new YearnVaultFactory(address(strategy), sdtDistributor);

        deal(address(this), 3e18);
    }

    function testCloneVault() external {
        factory.cloneAndInit(YEARN_GAUGE_1);
    }

    // function testReedem() external {
    //     // buy dYFI on curve
    //     ICurvePool(DYFIETH_POOL).exchange_underlying{value:5e17}(1, 0, 5e17, 0);
    //     emit log_uint(IERC20(DYFI).balanceOf(address(this)));
    //     uint256 dYfiBalance = IERC20(DYFI).balanceOf(address(this));
    //     uint256 ethRequired = IDyfiOption(DYFI_OPTION).eth_required(dYfiBalance);
    //     IERC20(DYFI).approve(DYFI_OPTION, 1000e18);
    //     IDyfiOption(DYFI_OPTION).redeem{value:ethRequired}(dYfiBalance);
    //     uint256 yearnBalance = IERC20(AddressBook.YFI).balanceOf(address(this));
    //     emit
    // }
}
