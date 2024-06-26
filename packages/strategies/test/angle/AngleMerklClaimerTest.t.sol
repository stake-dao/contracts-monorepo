// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/Test.sol";

//import {AddressBook} from "addressBook/AddressBook.sol";
import {AngleMerklClaimer} from "src/angle/claimer/AngleMerklClaimer.sol";
import {AngleVaultGamma} from "src/angle/vault/AngleVaultGamma.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Angle} from "address-book/protocols/1.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";

contract AngleMerklClaimerTest is Test {
    address public constant GUNI_AGEUR_ETH_LP = 0x857E0B2eD0E82D5cDEB015E77ebB873C47F99575;
    address public constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    uint256 public constant AMOUNT = 1e18;

    AngleVaultGamma public agEurEthVault = AngleVaultGamma(0xa0022debeB2275cf05B9c659493F89efe3AB89a6);
    ILiquidityGaugeStrat public agEurEthGauge = ILiquidityGaugeStrat(0x5DFdF492E52112D670bE9Df5bdC6b500E35479aC);
    AngleMerklClaimer public claimer;
    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public daoRecipient = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;
    address public accRecipient = 0x8cc02F4f383A11b989708437DbA6BB0628d7eE78;
    address public veSdtFeeProxyRecipient = 0xE92Aa77c3D8c7347950B2a8d4B2A0AdBF0c31054;

    IERC20 public angle = IERC20(Angle.ANGLE);

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 17529735);
        vm.selectFork(forkId);

        // Deploy Claimer
        claimer = new AngleMerklClaimer(deployer, daoRecipient, accRecipient, veSdtFeeProxyRecipient);
        vm.startPrank(deployer);
        // add ANGLE extra reward
        agEurEthGauge.add_reward(address(angle), address(claimer));

        // whitelist the claimer to claim ANGLE via the merkle
        agEurEthVault.toggleOnlyOperatorCanClaim();
        agEurEthVault.toggleOperator(address(claimer));
        agEurEthVault.approveClaimer(address(angle), address(claimer));
        vm.stopPrank();
    }

    function testClaimAndNotifyReward() public {
        uint256 baseFee = 10_000;
        uint256 amountToClaim = 8113624059808003;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](7);
        proofs[0][0] = bytes32(0xf278efdc294e3f7e2bfa6a3bd65313d17b2ef5cc535f7467d523181bf2cbbb7d);
        proofs[0][1] = bytes32(0x7ff4839ae5355bfb32bb2762e1125706713696ad01a34751da87d6fa70b5897c);
        proofs[0][2] = bytes32(0x5dbb786bc01685d31ef4ed2bc4baa201e268d1c242e0d562af9b70d5ce54400d);
        proofs[0][3] = bytes32(0xb7fcc719d40457c317c9b2ddc4fb934619d30bcea8b82ef1232a1839f563d429);
        proofs[0][4] = bytes32(0x2d4808fe73bd73b840e356b478027b99636ddd13f83198f4a9be453ea5b26555);
        proofs[0][5] = bytes32(0x60ca29286796dcf8245e2e3140df6c337b4ccd16b8039b3e551d86656dc27cf6);
        proofs[0][6] = bytes32(0xf3251bb75869e167066f09b73846bafda85e82dd2c7f1940336fb9783a513809);

        // balances before the claim
        uint256 gaugeBalanceBefore = angle.balanceOf(address(agEurEthGauge));
        uint256 claimerBalanceBefore = angle.balanceOf(address(this));
        uint256 daoRecipientBalanceBefore = angle.balanceOf(claimer.daoRecipient());
        uint256 accRecipientBalanceBefore = angle.balanceOf(claimer.accRecipient());
        uint256 veSdtFeeRecipientBalanceBefore = angle.balanceOf(claimer.veSdtFeeRecipient());

        // claim for agEur/Eth g-uni vault
        claimer.claimAndNotify(proofs, address(agEurEthVault), address(angle), amountToClaim);

        // balances after the claim
        uint256 gaugeReward = angle.balanceOf(address(agEurEthGauge)) - gaugeBalanceBefore;
        uint256 claimerReward = angle.balanceOf(address(this)) - claimerBalanceBefore;
        uint256 daoRecipientReward = angle.balanceOf(claimer.daoRecipient()) - daoRecipientBalanceBefore;
        uint256 accRecipientReward = angle.balanceOf(claimer.accRecipient()) - accRecipientBalanceBefore;
        uint256 veSdtRecipientReward = angle.balanceOf(claimer.veSdtFeeRecipient()) - veSdtFeeRecipientBalanceBefore;
        uint256 totalReward =
            gaugeReward + claimerReward + daoRecipientReward + accRecipientReward + veSdtRecipientReward;

        // asserts
        assertEq(totalReward * claimer.claimerFee() / baseFee, claimerReward);
        assertEq(totalReward * claimer.daoFee() / baseFee, daoRecipientReward);
        assertEq(totalReward * claimer.accFee() / baseFee, accRecipientReward);
        assertEq(totalReward * claimer.veSdtFeeFee() / baseFee, veSdtRecipientReward);
        assertEq(angle.balanceOf(address(claimer)), 0);
    }
}
