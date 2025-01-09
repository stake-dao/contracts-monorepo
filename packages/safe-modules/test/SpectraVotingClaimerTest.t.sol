// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "../src/SpectraVotingClaimer.sol";
import "../src/interfaces/ISpectraVoter.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface Safe {
    function enableModule(address module) external;
}

contract SpectraVotingClaimerTest is Test {
    address public constant DEPLOYER = address(0x428419Ad92317B09FE00675F181ac09c87D16450);
    address public constant SIGNER = address(0x88883560AD02A31D299865B1fCE0aaF350AaA553);
    address public immutable SD_SAFE = address(0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765);

    address public immutable SPECTRA = address(0x64FCC3A02eeEba05Ef701b7eed066c6ebD5d4E51);
    address public immutable USDC = address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    SpectraVotingClaimer spectraVotingClaimer;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("base"), 24_813_623);

        // Deploy the claimer
        vm.startPrank(DEPLOYER);
        spectraVotingClaimer = new SpectraVotingClaimer(DEPLOYER);
        vm.stopPrank();

        // Authorize the module in the Safe
        vm.startPrank(SD_SAFE);
        Safe(SD_SAFE).enableModule(address(spectraVotingClaimer));
        vm.stopPrank();
    }

    function testClaim() public {
        // At the block 24_813_623, we only have USDC and Spectra to claim
        vm.startPrank(DEPLOYER);

        bool canClaim = spectraVotingClaimer.canClaim();
        assertEq(canClaim, true);

        // Fetch all balances before the claim
        uint256 usdcSafeBalanceBeforeClaim = IERC20(USDC).balanceOf(spectraVotingClaimer.SD_SAFE());
        uint256 usdcTreasuryBalanceBeforeClaim = IERC20(USDC).balanceOf(spectraVotingClaimer.SD_TREASURY());
        uint256 usdcRecipientBalanceBeforeClaim = IERC20(USDC).balanceOf(spectraVotingClaimer.recipient());

        uint256 spectraSafeBalanceBeforeClaim = IERC20(SPECTRA).balanceOf(spectraVotingClaimer.SD_SAFE());
        uint256 spectraTreasuryBalanceBeforeClaim = IERC20(SPECTRA).balanceOf(spectraVotingClaimer.SD_TREASURY());
        uint256 spectraRecipientBalanceBeforeClaim = IERC20(SPECTRA).balanceOf(spectraVotingClaimer.recipient());

        // Perform the claim
        spectraVotingClaimer.claim();

        // Fetch balances after the claim
        uint256 usdcSafeBalanceAfterClaim = IERC20(USDC).balanceOf(spectraVotingClaimer.SD_SAFE());
        uint256 usdcTreasuryBalanceAfterClaim = IERC20(USDC).balanceOf(spectraVotingClaimer.SD_TREASURY());
        uint256 usdcRecipientBalanceAfterClaim = IERC20(USDC).balanceOf(spectraVotingClaimer.recipient());

        uint256 spectraSafeBalanceAfterClaim = IERC20(SPECTRA).balanceOf(spectraVotingClaimer.SD_SAFE());
        uint256 spectraTreasuryBalanceAfterClaim = IERC20(SPECTRA).balanceOf(spectraVotingClaimer.SD_TREASURY());
        uint256 spectraRecipientBalanceAfterClaim = IERC20(SPECTRA).balanceOf(spectraVotingClaimer.recipient());

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

    /// @notice should fail because connected with an unauthorize address
    function testClaimFail() public {
        vm.startPrank(SIGNER);

        bool canClaim = spectraVotingClaimer.canClaim();
        assertEq(canClaim, true);

        vm.expectRevert();
        spectraVotingClaimer.claim();

        vm.stopPrank();
    }

    function testClaimWithAssets() public {
        // At the block 24_813_623, we only have USDC and Spectra to claim
        vm.startPrank(DEPLOYER);

        bool canClaim = spectraVotingClaimer.canClaim();
        assertEq(canClaim, true);

        // Send some USDC and SPECTRA to the Safe
        uint256 defaultAmount = 100 ether;
        deal(USDC, spectraVotingClaimer.SD_SAFE(), defaultAmount);
        deal(SPECTRA, spectraVotingClaimer.SD_SAFE(), defaultAmount);

        // Fetch all balances before the claim
        uint256 usdcSafeBalanceBeforeClaim = IERC20(USDC).balanceOf(spectraVotingClaimer.SD_SAFE());
        uint256 usdcTreasuryBalanceBeforeClaim = IERC20(USDC).balanceOf(spectraVotingClaimer.SD_TREASURY());
        uint256 usdcRecipientBalanceBeforeClaim = IERC20(USDC).balanceOf(spectraVotingClaimer.recipient());

        uint256 spectraSafeBalanceBeforeClaim = IERC20(SPECTRA).balanceOf(spectraVotingClaimer.SD_SAFE());
        uint256 spectraTreasuryBalanceBeforeClaim = IERC20(SPECTRA).balanceOf(spectraVotingClaimer.SD_TREASURY());
        uint256 spectraRecipientBalanceBeforeClaim = IERC20(SPECTRA).balanceOf(spectraVotingClaimer.recipient());

        // Perform the claim
        spectraVotingClaimer.claim();

        // Fetch balances after the claim
        uint256 usdcSafeBalanceAfterClaim = IERC20(USDC).balanceOf(spectraVotingClaimer.SD_SAFE());
        uint256 usdcTreasuryBalanceAfterClaim = IERC20(USDC).balanceOf(spectraVotingClaimer.SD_TREASURY());
        uint256 usdcRecipientBalanceAfterClaim = IERC20(USDC).balanceOf(spectraVotingClaimer.recipient());

        uint256 spectraSafeBalanceAfterClaim = IERC20(SPECTRA).balanceOf(spectraVotingClaimer.SD_SAFE());
        uint256 spectraTreasuryBalanceAfterClaim = IERC20(SPECTRA).balanceOf(spectraVotingClaimer.SD_TREASURY());
        uint256 spectraRecipientBalanceAfterClaim = IERC20(SPECTRA).balanceOf(spectraVotingClaimer.recipient());

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
