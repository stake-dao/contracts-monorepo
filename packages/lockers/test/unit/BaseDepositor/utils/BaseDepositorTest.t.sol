// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {BaseDepositor as BaseDepositorContract} from "src/common/depositor/BaseDepositor.sol";
import {BaseTest} from "test/BaseTest.t.sol";

abstract contract BaseDepositorTest is BaseTest {
    IERC20 internal token;
    address internal locker;
    IERC20 internal minter;
    address internal gauge;
    uint256 internal maxLockDuration;
    address internal governance;
    BaseDepositor internal baseDepositor;

    function setUp() public virtual {
        // deploy the initial token
        MockERC20 mockToken = new MockERC20();
        mockToken.initialize("Token", "TKN", 18);
        token = IERC20(address(mockToken));

        // deploy the locker
        locker = makeAddr("locker");

        // deploy the minter
        MockERC20 mockMinter = new MockERC20();
        mockMinter.initialize("Minter", "MNTR", 18);
        minter = IERC20(address(mockMinter));

        // deploy the gauge
        gauge = makeAddr("gauge");

        // deploy the max lock duration
        maxLockDuration = 100;

        // set the governance
        governance = makeAddr("governance");

        // deploy the BaseDepositor contract
        vm.prank(governance);
        baseDepositor =
            new BaseDepositor(address(token), address(locker), address(minter), address(gauge), maxLockDuration);

        // // label the important addresses
        vm.label({account: address(token), newLabel: "Token"});
        vm.label({account: address(locker), newLabel: "Locker"});
        vm.label({account: address(minter), newLabel: "Minter"});
        vm.label({account: address(gauge), newLabel: "Gauge"});
        vm.label({account: address(governance), newLabel: "Governance"});
    }

    /// @notice Replace BaseDepositor with BaseDepositorHarness for testing
    /// @dev Only the runtime code stored for the BaseDepositor contract is replaced with BaseDepositorHarness's code.
    ///      The storage stays the same, every variables stored at BaseDepositor's construction time will be usable
    ///      by the BaseDepositorHarness implementation.
    // modifier _cheat_replaceBaseDepositorWithBaseDepositorHarness() {
    //     vm.prank(governance);
    //     _deployHarnessCode(
    //         "out/BaseDepositorHarness.t.sol/BaseDepositorHarness.json",
    //         abi.encode(address(token), address(locker), address(minter), address(gauge), maxLockDuration),
    //         address(locker)
    //     );

    //     baseDepositorHarness = BaseDepositorHarness(address(locker));

    //     baseDepositorHarness.transferGovernance(governance);
    //     vm.prank(governance);
    //     baseDepositorHarness.acceptGovernance();

    //     vm.label({account: address(baseDepositorHarness), newLabel: "LockbaseDepositorHarnesserHarness"});

    //     _;
    // }
}

contract BaseDepositor is BaseDepositorContract {
    constructor(address _token, address _locker, address _minter, address _gauge, uint256 _maxLockDuration)
        BaseDepositorContract(_token, _locker, _minter, _gauge, _maxLockDuration)
    {}
}
