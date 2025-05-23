// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Enum} from "@safe/contracts/Safe.sol";
import {Common} from "address-book/src/CommonBase.sol";
import {DAO} from "address-book/src/DAOBase.sol";
import {SpectraLocker} from "address-book/src/SpectraBase.sol";
import {Test} from "forge-std/src/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ILocker, ISafe} from "src/common/interfaces/spectra/stakedao/ILocker.sol";
import {SpectraVotingClaimer} from "src/voters/SpectraVotingClaimer.sol";

contract SpectraVotingClaimerTest is Test {
    address public immutable WETH = Common.WETH;
    address public immutable GHO = Common.GHO;

    SpectraVotingClaimer internal spectraVotingClaimer;

    function _enableModule(address _locker, address _module) internal {
        vm.prank(DAO.GOVERNANCE);
        ILocker(_locker).execTransaction(
            _locker,
            0,
            abi.encodeWithSelector(ISafe.enableModule.selector, _module),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            abi.encodePacked(uint256(uint160(DAO.GOVERNANCE)), uint8(0), uint256(1))
        );
    }

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("base"), 28_965_463);

        // Deploy the claimer
        spectraVotingClaimer = new SpectraVotingClaimer(msg.sender, address(SpectraLocker.LOCKER));

        // Enable the claimer as a Safe module of the locker Safe Account, as this is the new version of the locker.
        _enableModule(spectraVotingClaimer.LOCKER(), address(spectraVotingClaimer));
        assertEq(ILocker(spectraVotingClaimer.LOCKER()).isModuleEnabled(address(spectraVotingClaimer)), true);

        // Allow this test to call the claim function
        vm.prank(spectraVotingClaimer.governance());
        spectraVotingClaimer.allowAddress(address(this));

        vm.label(address(spectraVotingClaimer), "SPECTRA_VOTING_CLAIMER");
        vm.label(spectraVotingClaimer.LOCKER(), "SPECTRA_LOCKER");
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
    }
}
