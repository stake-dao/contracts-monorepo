// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import {Test} from "forge-std/src/Test.sol";
import {SpectraVotingClaimer} from "src/SpectraVotingClaimer.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SpectraLocker} from "address-book/src/SpectraBase.sol";
import {Common} from "address-book/src/CommonBase.sol";

interface Safe {
    function enableModule(address module) external;
}

contract SpectraVotingClaimerTest is Test {
    address public immutable WETH = Common.WETH;
    address public immutable GHO = Common.GHO;

    SpectraVotingClaimer spectraVotingClaimer;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("base"), 28_965_463);

        // Deploy the claimer
        spectraVotingClaimer = new SpectraVotingClaimer(msg.sender);
        address locker = address(spectraVotingClaimer.LOCKER());

        // Authorize the module in the Safe
        vm.startPrank(locker);
        Safe(locker).enableModule(address(spectraVotingClaimer));
        vm.stopPrank();
    }

    function testClaim() public {
        // At the block 28_965_463, we only have GHO and WETH to claim

        bool canClaim = spectraVotingClaimer.canClaim();
        assertEq(canClaim, true);

        // Fetch all balances before the claim
        uint256 usdcSafeBalanceBeforeClaim = IERC20(WETH).balanceOf(spectraVotingClaimer.LOCKER());
        uint256 usdcTreasuryBalanceBeforeClaim = IERC20(WETH).balanceOf(spectraVotingClaimer.SD_TREASURY());
        uint256 usdcRecipientBalanceBeforeClaim = IERC20(WETH).balanceOf(spectraVotingClaimer.recipient());

        uint256 spectraSafeBalanceBeforeClaim = IERC20(GHO).balanceOf(spectraVotingClaimer.LOCKER());
        uint256 spectraTreasuryBalanceBeforeClaim = IERC20(GHO).balanceOf(spectraVotingClaimer.SD_TREASURY());
        uint256 spectraRecipientBalanceBeforeClaim = IERC20(GHO).balanceOf(spectraVotingClaimer.recipient());

        // Perform the claim
        spectraVotingClaimer.claim();

        // Fetch balances after the claim
        uint256 usdcSafeBalanceAfterClaim = IERC20(WETH).balanceOf(spectraVotingClaimer.LOCKER());
        uint256 usdcTreasuryBalanceAfterClaim = IERC20(WETH).balanceOf(spectraVotingClaimer.SD_TREASURY());
        uint256 usdcRecipientBalanceAfterClaim = IERC20(WETH).balanceOf(spectraVotingClaimer.recipient());

        uint256 spectraSafeBalanceAfterClaim = IERC20(GHO).balanceOf(spectraVotingClaimer.LOCKER());
        uint256 spectraTreasuryBalanceAfterClaim = IERC20(GHO).balanceOf(spectraVotingClaimer.SD_TREASURY());
        uint256 spectraRecipientBalanceAfterClaim = IERC20(GHO).balanceOf(spectraVotingClaimer.recipient());

        // Compare balances
        // Should be equals for the Safe
        assertEq(usdcSafeBalanceBeforeClaim, usdcSafeBalanceAfterClaim);
        assertEq(spectraSafeBalanceBeforeClaim, spectraSafeBalanceAfterClaim);

        // And should be higher for the recipient and treasury
        assertGt(usdcTreasuryBalanceAfterClaim, usdcTreasuryBalanceBeforeClaim);
        assertGt(spectraTreasuryBalanceAfterClaim, spectraTreasuryBalanceBeforeClaim);
        assertGt(usdcRecipientBalanceAfterClaim, usdcRecipientBalanceBeforeClaim);
        assertGt(spectraRecipientBalanceAfterClaim, spectraRecipientBalanceBeforeClaim);

        vm.stopPrank();
    }
}
