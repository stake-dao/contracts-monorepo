// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {PreLaunchLocker, ILiquidityGaugeV4} from "src/common/locker/PreLaunchLocker.sol";
import {sdToken as SdToken} from "src/common/token/sdToken.sol";
import {BaseTest} from "test/BaseTest.t.sol";
import {PreLaunchLockerHarness} from "./PreLaunchLockerHarness.t.sol";

abstract contract PreLaunchLockerTest is BaseTest {
    MockERC20 internal token;
    SdToken internal sdToken;
    ILiquidityGaugeV4 internal gauge;
    address internal governance;
    PreLaunchLocker internal locker;
    PreLaunchLockerHarness internal lockerHarness;

    function setUp() public virtual {
        // deploy the initial token
        token = new MockERC20();
        token.initialize("Token", "TKN", 18);

        // deploy the sdToken
        sdToken = new SdToken("sdToken", "sdTKN");

        // deploy the gauge
        gauge = ILiquidityGaugeV4(address(new GaugeMock(address(sdToken))));

        // fast forward the time to avoid the block.timestamp to be 0
        skip(3600);

        // deploy the locker
        governance = makeAddr("governance");
        vm.prank(governance);
        locker = new PreLaunchLocker(address(token), address(sdToken), address(gauge));

        // set the operator of the sdToken to the locker
        sdToken.setOperator(address(locker));

        // label the important addresses
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

contract GaugeMock is MockERC20 {
    address private sdToken;

    constructor(address token) {
        sdToken = token;

        initialize("Gauge Token", "gTKN", 18);
    }

    function deposit(uint256 amount, address receiver, bool) external {
        SdToken(sdToken).transferFrom(msg.sender, address(this), amount);
        _mint(receiver, amount);
    }

    function staking_token() external view returns (address) {
        return sdToken;
    }

    function withdraw(uint256 amount, bool) external {
        _burn(msg.sender, amount);

        SdToken(sdToken).transfer(msg.sender, amount);
    }
}
