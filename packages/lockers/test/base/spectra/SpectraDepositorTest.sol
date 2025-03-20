// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {BaseSpectraTokenTest} from "test/base/spectra/common/BaseSpectraTokenTest.sol";
import {ISpectraLocker} from "src/common/interfaces/spectra/spectra/ISpectraLocker.sol";
import {ISdSpectraDepositor} from "src/common/interfaces/spectra/stakedao/ISdSpectraDepositor.sol";

contract SpectraTest is BaseSpectraTokenTest {
    constructor() {}

    address alice = address(0x1);
    address initializer = address(0x2);

    // interface for veSpectra
    ISpectraLocker veSpectraLocker = ISpectraLocker(address(veSpectra));
    // interface for sdSpectra depositor
    ISdSpectraDepositor spectraDepositor;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("base"));
        vm.selectFork(forkId);
        _deploySpectraIntegration();

        spectraDepositor = ISdSpectraDepositor(address(depositor));

        deal(address(spectraToken), address(this), 1_000_000 ether);
        deal(address(spectraToken), address(initializer), 1 ether);
    }

    /////////////////////////
    //  UTILITY FUNCTIONS
    ////////////////////////

    function _depositTokens(uint256 _amount, bool _lock, bool _stake, address _user) public {
        spectraToken.approve(address(spectraDepositor), _amount);
        spectraDepositor.deposit(_amount, _lock, _stake, _user);
    }

    function _createVeNft(uint256 _amount, uint256 _duration) public returns (uint256) {
        spectraToken.approve(address(veSpectraLocker), _amount);
        return veSpectraLocker.createLock(_amount, _duration);
    }

    function _initializeLocker() public {
        vm.startPrank(initializer);
        spectraToken.approve(address(spectraDepositor), 1 ether);
        spectraDepositor.createLock(1 ether);
        vm.stopPrank();
    }

    /////////////////////////
    //  TEST FUNCTIONS
    ////////////////////////

    function test_canDeploySafeProxy() public {}

    function test_canCreateLock() public {
        uint256 _amount = 1 ether;

        // Check initial locker state
        uint256 createdTokenId = veSpectraLocker.ownerToNFTokenIdList(locker, 0);
        assertEq(createdTokenId, 0);
        assertEq(createdTokenId, spectraDepositor.spectraLockedTokenId());

        spectraToken.approve(address(spectraDepositor), 2 * _amount);

        spectraDepositor.createLock(_amount);

        // Check that sdSPECTRA-gauge is minted
        assertEq(ISdToken(sdToken).balanceOf(address(this)), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), _amount);

        // Check that locker owns 1 NFT
        assertEq(veSpectra.balanceOf(locker), 1);

        // Check locker state
        createdTokenId = veSpectraLocker.ownerToNFTokenIdList(locker, 0);
        assertGt(createdTokenId, 0);
        assertEq(createdTokenId, spectraDepositor.spectraLockedTokenId());

        ISpectraLocker.LockedBalance memory lockedBalance = veSpectraLocker.locked(createdTokenId);
        assertEq(lockedBalance.amount, _amount);
        assertTrue(lockedBalance.isPermanent);

        // Can't recreate the lock
        vm.expectRevert(ISdSpectraDepositor.LockAlreadyExists.selector);
        spectraDepositor.createLock(_amount);
    }

    function test_canDepositTokensWithoutStake() public {
        uint256 _amount = 1 ether;

        // Check initial locker state, no nft so id should be 0
        uint256 initialTokenId = veSpectraLocker.ownerToNFTokenIdList(locker, 0);
        assertEq(initialTokenId, 0);
        assertEq(spectraDepositor.spectraLockedTokenId(), 0);

        // ------ DEPOSIT -------
        _depositTokens(_amount, true, false, address(this));

        // Check that sdToken is minted
        assertEq(ISdToken(sdToken).balanceOf(address(this)), _amount);
        assertEq(liquidityGauge.balanceOf(address(this)), 0);
        assertEq(veSpectra.balanceOf(locker), 1);

        // Check locker state, lock created so the token id shouldn't be 0, and should be stored in spectraDepositor.
        // amount field of the token id should be amount, and token lock should be permanent
        uint256 createdTokenId = veSpectraLocker.ownerToNFTokenIdList(locker, 0);
        assertGt(createdTokenId, 0);
        assertEq(createdTokenId, spectraDepositor.spectraLockedTokenId());

        ISpectraLocker.LockedBalance memory lockedBalance = veSpectraLocker.locked(createdTokenId);
        assertEq(lockedBalance.amount, _amount);
        assertTrue(lockedBalance.isPermanent);

        // check that sdSPECTRA is minted
        assertEq(ISdToken(sdToken).balanceOf(address(this)), _amount);
        assertEq(liquidityGauge.balanceOf(address(this)), 0);

        // ------ DEPOSIT -------
        _depositTokens(_amount, true, false, address(this));

        // Check that sdSPECTRA is minted
        assertEq(ISdToken(sdToken).balanceOf(address(this)), 2 * _amount);
        assertEq(veSpectra.balanceOf(locker), 1);

        // Check locker state, token id shouldn't change since creation, and amount should increase
        uint256 checkedTokenId = veSpectraLocker.ownerToNFTokenIdList(locker, 0);
        assertEq(createdTokenId, checkedTokenId);
        assertEq(checkedTokenId, spectraDepositor.spectraLockedTokenId());

        lockedBalance = veSpectraLocker.locked(createdTokenId);
        assertEq(lockedBalance.amount, 2 * _amount);
        assertTrue(lockedBalance.isPermanent);

        // check that sdSPECTRA is minted
        assertEq(ISdToken(sdToken).balanceOf(address(this)), 2 * _amount);
        assertEq(liquidityGauge.balanceOf(address(this)), 0);
    }

    function test_canDepositTokensAndStake() public {
        uint256 _amount = 1 ether;

        _depositTokens(_amount, true, true, address(this));

        // check that sdSPECTRA-gauge is minted
        assertEq(ISdToken(sdToken).balanceOf(address(this)), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), _amount);
    }

    function test_canDepositToDifferentRecipientWithoutStake() public {
        uint256 _amount = 10 ether;

        _depositTokens(_amount, true, false, alice);

        // check that sdSPECTRA is minted for the custom recipîent
        assertEq(ISdToken(sdToken).balanceOf(alice), _amount);
        assertEq(liquidityGauge.balanceOf(alice), 0);
    }

    function test_canDepositToDifferentRecipientAndStake() public {
        uint256 _amount = 10 ether;

        _depositTokens(_amount, true, true, alice);

        // check that gauge sdSPECTRA-gauge is minted for the custom recipient
        assertEq(ISdToken(sdToken).balanceOf(alice), 0);
        assertEq(liquidityGauge.balanceOf(alice), _amount);
    }

    function test_cantDepositZeroTokens() public {
        spectraToken.approve(address(spectraDepositor), 1 ether);

        vm.expectRevert();
        spectraDepositor.deposit(0, true, true, address(0));
    }

    function test_cantDepositToZeroAddress() public {
        spectraToken.approve(address(spectraDepositor), 1 ether);

        vm.expectRevert();
        spectraDepositor.deposit(1 ether, true, true, address(0));
    }

    function test_cantDepositVeSpectraNftWithoutInitialization() public {
        uint256 _amount = 10 ether;

        // Create a veNFT
        uint256 tokenId = _createVeNft(_amount, 2 * 365 days);

        veSpectraLocker.setApprovalForAll(locker, true);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.expectRevert();
        spectraDepositor.deposit(tokenIds, false, address(this));
    }

    function test_canDepositVeSpectraNftWithoutStake() public {
        _initializeLocker();

        //Store initial token id and state of the locker
        uint256 initialTokenId = veSpectraLocker.ownerToNFTokenIdList(locker, 0);
        ISpectraLocker.LockedBalance memory lockedBalanceBefore = veSpectraLocker.locked(initialTokenId);

        uint256 _amount = 10 ether;

        // Create a veNFT
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _createVeNft(_amount, 2 * 365 days);

        veSpectraLocker.setApprovalForAll(locker, true);
        // ------ DEPOSIT -------
        spectraDepositor.deposit(tokenIds, false, address(this));

        // Check that sdSPECTRA is minted
        assertEq(ISdToken(sdToken).balanceOf(address(this)), _amount);
        assertEq(liquidityGauge.balanceOf(address(this)), 0);

        // Check that locker only holds 1 nft
        assertEq(veSpectra.balanceOf(locker), 1);

        // Check locker state, token id shouldn't change since creation, and amount should increase
        uint256 checkedTokenId = veSpectraLocker.ownerToNFTokenIdList(locker, 0);
        assertEq(initialTokenId, checkedTokenId);
        assertEq(checkedTokenId, spectraDepositor.spectraLockedTokenId());

        ISpectraLocker.LockedBalance memory lockedBalance = veSpectraLocker.locked(checkedTokenId);
        assertEq(lockedBalance.amount - lockedBalanceBefore.amount, _amount);
        assertTrue(lockedBalance.isPermanent);
    }

    function test_canDepositVeSpectraNftAndStake() public {
        _initializeLocker();

        //Store initial token id and state of the locker
        uint256 initialTokenId = veSpectraLocker.ownerToNFTokenIdList(locker, 0);
        ISpectraLocker.LockedBalance memory lockedBalanceBefore = veSpectraLocker.locked(initialTokenId);

        uint256 _amount = 10 ether;

        // Create a veNFT
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _createVeNft(_amount, 2 * 365 days);

        veSpectraLocker.setApprovalForAll(locker, true);
        // ------ DEPOSIT -------
        spectraDepositor.deposit(tokenIds, true, address(this));

        // Check that sdSPECTRA-gauge is minted
        assertEq(ISdToken(sdToken).balanceOf(address(this)), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), _amount);

        // Check that locker only holds 1 nft
        assertEq(veSpectra.balanceOf(locker), 1);

        // Check locker state, token id shouldn't change since creation, and amount should increase
        uint256 checkedTokenId = veSpectraLocker.ownerToNFTokenIdList(locker, 0);
        assertEq(initialTokenId, checkedTokenId);
        assertEq(checkedTokenId, spectraDepositor.spectraLockedTokenId());

        ISpectraLocker.LockedBalance memory lockedBalance = veSpectraLocker.locked(checkedTokenId);
        assertEq(lockedBalance.amount - lockedBalanceBefore.amount, _amount);
        assertTrue(lockedBalance.isPermanent);
    }

    function test_canDepositVeSpectraNftWithPermanentLock() public {
        _initializeLocker();

        //Store initial token id and state of the locker
        uint256 initialTokenId = veSpectraLocker.ownerToNFTokenIdList(locker, 0);
        ISpectraLocker.LockedBalance memory lockedBalanceBefore = veSpectraLocker.locked(initialTokenId);

        uint256 _amount = 10 ether;

        // Create a veNFT
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _createVeNft(_amount, 2 * 365 days);
        veSpectraLocker.lockPermanent(tokenIds[0]);

        // Check that the new nft is permanently locked
        assertTrue(veSpectraLocker.locked(tokenIds[0]).isPermanent);

        veSpectraLocker.setApprovalForAll(locker, true);
        // ------ DEPOSIT -------
        spectraDepositor.deposit(tokenIds, true, address(this));

        // Check that sdSPECTRA-gauge is minted
        assertEq(ISdToken(sdToken).balanceOf(address(this)), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), _amount);

        // Check that locker only holds 1 nft
        assertEq(veSpectra.balanceOf(locker), 1);

        // Check locker state, token id shouldn't change since creation, and amount should increase
        uint256 checkedTokenId = veSpectraLocker.ownerToNFTokenIdList(locker, 0);
        assertEq(initialTokenId, checkedTokenId);
        assertEq(checkedTokenId, spectraDepositor.spectraLockedTokenId());

        ISpectraLocker.LockedBalance memory lockedBalance = veSpectraLocker.locked(checkedTokenId);
        assertEq(lockedBalance.amount - lockedBalanceBefore.amount, _amount);
        assertTrue(lockedBalance.isPermanent);
    }

    function test_canDepositMultipleVeSpectraNft() public {
        _initializeLocker();

        //Store initial token id and state of the locker
        uint256 initialTokenId = veSpectraLocker.ownerToNFTokenIdList(locker, 0);
        ISpectraLocker.LockedBalance memory lockedBalanceBefore = veSpectraLocker.locked(initialTokenId);

        uint256 _amount = 10 ether;

        // Create a veNFT
        uint256[] memory tokenIds = new uint256[](5);
        tokenIds[0] = _createVeNft(3 * _amount, 2 * 365 days);
        tokenIds[1] = _createVeNft(_amount, 4 * 365 days);
        tokenIds[2] = _createVeNft(2 * _amount, 800 days);
        tokenIds[3] = _createVeNft(2 * _amount, 1200 days);
        tokenIds[4] = _createVeNft(12 * _amount, 14 days);

        // Lock permanently some of the new veNFT
        veSpectraLocker.lockPermanent(tokenIds[0]);
        veSpectraLocker.lockPermanent(tokenIds[2]);

        // Check that the new nft are permanently locked
        assertTrue(veSpectraLocker.locked(tokenIds[0]).isPermanent);
        assertFalse(veSpectraLocker.locked(tokenIds[1]).isPermanent);
        assertTrue(veSpectraLocker.locked(tokenIds[2]).isPermanent);
        assertFalse(veSpectraLocker.locked(tokenIds[3]).isPermanent);
        assertFalse(veSpectraLocker.locked(tokenIds[4]).isPermanent);

        veSpectraLocker.setApprovalForAll(locker, true);
        // ------ DEPOSIT -------
        spectraDepositor.deposit(tokenIds, false, address(this));

        // Check that sdSPECTRA is minted
        assertEq(ISdToken(sdToken).balanceOf(address(this)), 20 * _amount); // Total of all veNFT amounts
        assertEq(liquidityGauge.balanceOf(address(this)), 0);

        // Check that locker only holds 1 nft
        assertEq(veSpectra.balanceOf(locker), 1);

        // Check locker state, token id shouldn't change since creation, and amount should increase
        uint256 checkedTokenId = veSpectraLocker.ownerToNFTokenIdList(locker, 0);
        assertEq(initialTokenId, checkedTokenId);
        assertEq(checkedTokenId, spectraDepositor.spectraLockedTokenId());

        ISpectraLocker.LockedBalance memory lockedBalance = veSpectraLocker.locked(checkedTokenId);
        assertEq(lockedBalance.amount - lockedBalanceBefore.amount, 20 * _amount);
        assertTrue(lockedBalance.isPermanent);
    }

    function test_canDepositVeSpectraNftDifferentRecipient() public {
        _initializeLocker();

        uint256 _amount = 10 ether;

        // Create a veNFT
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _createVeNft(_amount, 1 * 365 days);

        veSpectraLocker.setApprovalForAll(locker, true);
        // ------ DEPOSIT -------
        spectraDepositor.deposit(tokenIds, true, alice);

        // Check that sdSPECTRA-gauge is minted
        assertEq(ISdToken(sdToken).balanceOf(alice), 0);
        assertEq(liquidityGauge.balanceOf(alice), _amount);
    }
}
