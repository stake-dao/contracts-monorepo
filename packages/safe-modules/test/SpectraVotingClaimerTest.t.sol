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
    address public immutable SD_SAFE = address(0xC0295F271c4fD531d436F55b0ceF4Cc316188046);

    address public immutable WETH = address(0x4200000000000000000000000000000000000006);
    address public immutable GHO = address(0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee);

    SpectraVotingClaimer spectraVotingClaimer;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("base"), 28_965_463);

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
        // At the block 28_965_463, we only have GHO and WETH to claim
        vm.startPrank(DEPLOYER);

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
