// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AutocompoundedVault} from "src/integrations/yieldnest/AutocompoundedVault.sol";
import {AutocompoundedVaultTest} from "test/unit/AutocompoundedVault/utils/AutocompoundedVaultTest.t.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract AutocompoundedVault__getCurrentStream is AutocompoundedVaultTest {
    AutocompoundedVault internal autocompoundedVault;

    function setUp() public override {
        super.setUp();

        autocompoundedVault = new AutocompoundedVault(address(protocolController));
    }

    function test_ReturnsNoRemainingTokenAndTimeIfNoStreamStarted() external view {
        // it returns no remaining token and time if no stream started

        (uint256 amount, uint256 remainingToken, uint128 start, uint128 end, uint128 remainingTime) =
            autocompoundedVault.getCurrentStream();

        assertEq(amount, 0);
        assertEq(remainingToken, 0);
        assertEq(start, 0);
        assertEq(end, 0);
        assertEq(remainingTime, 0);
    }

    function test_ReturnsNoRemainingTokenAndTimeIfTheStreamFinished() external {
        // it returns no remaining token and time if the stream finished

        // set a reward stream
        deal(autocompoundedVault.asset(), address(this), 1e18);
        IERC20(autocompoundedVault.asset()).approve(address(autocompoundedVault), 1e18);
        autocompoundedVault.setRewards(1e18);

        // warp to the end of the streaming period
        vm.warp(block.timestamp + autocompoundedVault.STREAMING_PERIOD());

        (uint256 amount, uint256 remainingToken, uint128 start, uint128 end, uint128 remainingTime) =
            autocompoundedVault.getCurrentStream();

        assertEq(amount, 1e18);
        assertEq(remainingToken, 0);
        assertEq(start, block.timestamp - autocompoundedVault.STREAMING_PERIOD());
        assertEq(end, block.timestamp);
        assertEq(remainingTime, 0);
    }

    function test_ReturnsCalculatedValuesIfTheStreamIsOngoing() external {
        // it returns calculated values if the stream is ongoing

        // set a reward stream
        deal(autocompoundedVault.asset(), address(this), 1e20);
        IERC20(autocompoundedVault.asset()).approve(address(autocompoundedVault), 1e20);
        autocompoundedVault.setRewards(1e20);

        // warp 1 day to the futre
        uint256 startTimestamp = block.timestamp;
        vm.warp(startTimestamp + 1 days);

        // fetch and check the current stream
        (uint256 amount, uint256 remainingToken, uint128 start, uint128 end, uint128 remainingTime) =
            autocompoundedVault.getCurrentStream();

        assertEq(amount, 1e20);
        assertEq(start, startTimestamp);
        assertEq(end, startTimestamp + autocompoundedVault.STREAMING_PERIOD());
        assertEq(remainingTime, autocompoundedVault.STREAMING_PERIOD() - 1 days);
        assertEq(
            remainingToken,
            (1e20 * (autocompoundedVault.STREAMING_PERIOD() - 1 days)) / autocompoundedVault.STREAMING_PERIOD()
        );
    }
}
