// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";
import {PreLaunchLockerHarness} from "./PreLaunchLockerHarness.t.sol";
import {BaseTest} from "test/BaseTest.t.sol";
import {sdToken as SdToken} from "src/common/token/sdToken.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";

abstract contract PreLaunchLockerTest is BaseTest {
    address internal token;
    SdToken internal sdToken;
    ILiquidityGauge internal gauge;
    address internal governance;
    PreLaunchLocker internal locker;
    PreLaunchLockerHarness internal lockerHarness;

    function setUp() public virtual {
        token = makeAddr("token");
        sdToken = new SdToken("sdToken", "sdTOKEN");
        governance = makeAddr("governance");
        gauge = ILiquidityGauge(address(new GaugeMock(address(sdToken))));

        vm.prank(governance);
        locker = new PreLaunchLocker(token, address(sdToken), address(gauge));

        vm.label({account: address(locker), newLabel: "Locker"});
        vm.label({account: address(governance), newLabel: "Governance"});
        vm.label({account: address(token), newLabel: "Token"});
        vm.label({account: address(sdToken), newLabel: "SdToken"});
        vm.label({account: address(gauge), newLabel: "Gauge"});
    }

    /// @notice Replace PreLaunchLocker with PreLaunchLockerHarness for testing
    /// @dev Only the runtime code stored for the PreLaunchLocker contract is replaced with PreLaunchLockerHarness's code.
    ///      The storage stays the same, every variables stored at PreLaunchLocker's construction time will be usable
    ///      by the PreLaunchLockerHarness implementation.
    modifier _cheat_replacePreLaunchLockerWithPreLaunchLockerHarness() {
        vm.prank(governance);
        _deployHarnessCode(
            "out/PreLaunchLockerHarness.t.sol/PreLaunchLockerHarness.json",
            abi.encode(address(token), address(sdToken), address(gauge)),
            address(locker)
        );

        lockerHarness = PreLaunchLockerHarness(address(locker));
        vm.label({account: address(lockerHarness), newLabel: "LockerHarness"});

        _;
    }
}

contract GaugeMock {
    // mapping(address => uint256) public balances;
    address private sdToken;

    constructor(address token) {
        sdToken = token;
    }

    function deposit(uint256 amount, address receiver) external {
        SdToken(sdToken).transferFrom(msg.sender, address(this), amount);
        // balances[receiver] += amount;
    }

    function lp_token() external view returns (address) {
        return sdToken;
    }
}

contract ExtendedMockERC20 is MockERC20 {
    function _cheat_mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
