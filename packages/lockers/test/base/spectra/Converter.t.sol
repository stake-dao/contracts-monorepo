// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Converter} from "src/mainnet/apwine/Converter.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {BaseSpectraTokenTest} from "test/base/spectra/common/BaseSpectraTokenTest.sol";
import {ISpectraLocker} from "src/common/interfaces/spectra/spectra/ISpectraLocker.sol";
import {ISdSpectraDepositor} from "src/common/interfaces/spectra/stakedao/ISdSpectraDepositor.sol";

contract SpectraTest is BaseSpectraTokenTest {
    
    Converter public converter;
    ISdSpectraDepositor spectraDepositor;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address initializer = makeAddr("initializer");

    uint256 sdAPWineSupply = 1459843245173853310837177;
    uint256 totalSdSpectraToDistribute = sdAPWineSupply * 20;

    uint256 ratio = 20 ether;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("base"));
        _deploySpectraIntegration();

        spectraDepositor = ISdSpectraDepositor(address(depositor));
        
        deal(address(spectraToken), address(initializer), 1 ether);

        _initializeLocker();

        // Force locked tokenid to not be in "voted" state
        vm.prank(ISpectraLocker(address(veSpectra)).voter());
        ISpectraLocker(address(veSpectra)).voting(592, false);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 592;

        // Deposit existing NFT 
        vm.startPrank(GOVERNANCE);
        veSpectra.setApprovalForAll(locker, true);
        ISdSpectraDepositor(address(depositor)).deposit(tokenIds, false, GOVERNANCE);
        vm.stopPrank();

        // Base, destination chain id is not necessary. 
        // sdAPWine supply : 1459843245173853310837177
        // We use the balance of the governance after a deposit to have the amount of sdSEPCTRA to distribute
        converter = new Converter(sdToken, address(liquidityGauge), address(this), 8453, 20 ether); 

        vm.prank(GOVERNANCE);
        IERC20(sdToken).transfer(address(converter), totalSdSpectraToDistribute);
    }

    /////////////////////////
    //  UTILITY FUNCTIONS
    ////////////////////////


    function _initializeLocker() public {
        vm.startPrank(initializer);
        spectraToken.approve(address(spectraDepositor), 1 ether);
        spectraDepositor.createLock(1 ether);
        vm.stopPrank();
    }

    /////////////////////////
    //  TEST FUNCTIONS
    ////////////////////////

    function test_initialState() public view {
        assertEq(IERC20(sdToken).balanceOf(address(converter)), totalSdSpectraToDistribute);
        assertEq(converter.conversionRatio(), ratio);
    }

    function test_resolveConvert() public {
        // Simulate data set by La poste to call convert contract
        bytes memory payload = abi.encode(Converter.Payload({amount : 11 ether, receiver : bob}));

        // 1 for chain Id, sender should be converter address in mainnet
        converter.receiveMessage(1, address(converter), payload);

        // receiver is bob, bob should have 11 * convertion ratio sdSPECTRA gauge
        assertEq(IERC20(sdToken).balanceOf(bob), 0);
        assertEq(liquidityGauge.balanceOf(bob), 11 ether * ratio /10**18);
    }

    function test_resolveConvertAllSupply() public {
        // Simulate data set by La poste to call convert contract
        bytes memory payload = abi.encode(Converter.Payload({amount : sdAPWineSupply, receiver : alice}));

        // 1 for chain Id, sender should be converter address in mainnet
        converter.receiveMessage(1, address(converter), payload);

        // receiver is alice, bob should have all the tokens to redeem
        assertEq(IERC20(sdToken).balanceOf(alice), 0);
        assertEq(liquidityGauge.balanceOf(alice), totalSdSpectraToDistribute);
    }

    function test_cantResolveConvertIfWrongOrigin() public {
        // Simulate data set by La poste to call convert contract
        bytes memory payload = abi.encode(Converter.Payload({amount : sdAPWineSupply, receiver : alice}));

        // sender should revert if not the converter address in mainnet
        vm.expectRevert(Converter.InvalidSender.selector);
        converter.receiveMessage(1, alice, payload);

        // msg.sender should revert if not the la poste address
        vm.startPrank(alice);
        vm.expectRevert(Converter.NotLaPoste.selector);
        converter.receiveMessage(1, address(this), payload);
        vm.stopPrank();
    }
}
