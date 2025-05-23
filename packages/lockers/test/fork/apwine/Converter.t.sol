// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SpectraLocker} from "address-book/src/SpectraEthereum.sol";
import {Test} from "forge-std/src/Test.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {APWine2SpectraConverter} from "src/base/spectra/APWine2SpectraConverter.sol";
import {ILaPoste} from "src/common/interfaces/ILaPoste.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";

contract ConverterTest is Test {
    ERC20 public sdToken;
    ERC20 public sdTokenGauge;
    APWine2SpectraConverter public converter;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        sdToken = ERC20(SpectraLocker.SDTOKEN);
        sdTokenGauge = ERC20(SpectraLocker.GAUGE);

        // Mainnet, conversion rate is not necessary
        converter = new APWine2SpectraConverter(SpectraLocker.SDTOKEN, SpectraLocker.GAUGE, address(this), 8453, 0);

        vm.prank(ISdToken(SpectraLocker.SDTOKEN).operator());
        ISdToken(SpectraLocker.SDTOKEN).setOperator(address(converter));
    }

    function sendMessage(ILaPoste.MessageParams memory messageParams, uint256 additionalGasLimit, address _receiver)
        public
        payable
    {
        // check parameters
        assertEq(additionalGasLimit, 200 gwei);
        assertEq(msg.value, 10 ** 16);
        assertEq(_receiver, bob);
        assertEq(messageParams.tokens.length, 0);
        assertEq(messageParams.to, address(converter));
        assertEq(messageParams.destinationChainId, 8453);
        assertEq(messageParams.payload, abi.encode(APWine2SpectraConverter.Payload({amount: 11 ether, receiver: bob})));
    }

    function test_initConversion() public {
        deal(address(sdToken), alice, 1 ether);
        deal(address(sdTokenGauge), alice, 10 ether);
        deal(alice, 1 ether);

        // Check that alice owns tokens
        assertGt(sdToken.balanceOf(alice), 0);
        assertGt(sdTokenGauge.balanceOf(alice), 0);

        vm.startPrank(alice);
        sdToken.approve(address(converter), type(uint256).max);
        sdTokenGauge.approve(address(converter), type(uint256).max);
        converter.initConvert{value: 10 ** 16}(bob, 200 gwei);
        vm.stopPrank();

        // Check that tokens are burnt from alice
        assertEq(sdToken.balanceOf(alice), 0);
        assertEq(sdTokenGauge.balanceOf(alice), 0);
    }

    function test_cantInitiateWithZeroAddressAsReceiver() public {
        deal(address(sdToken), alice, 1 ether);
        deal(address(sdTokenGauge), alice, 10 ether);
        deal(alice, 1 ether);

        // Check that alice owns tokens
        assertGt(sdToken.balanceOf(alice), 0);
        assertGt(sdTokenGauge.balanceOf(alice), 0);

        vm.startPrank(alice);
        sdToken.approve(address(converter), type(uint256).max);
        sdTokenGauge.approve(address(converter), type(uint256).max);

        vm.expectRevert(APWine2SpectraConverter.ZeroAddress.selector);
        converter.initConvert{value: 10 ** 16}(address(0), 200 gwei);
        vm.stopPrank();
    }

    function test_cantInitiateWithZeroTokens() public {
        deal(alice, 1 ether);

        // Check that alice owns tokens
        assertEq(sdToken.balanceOf(alice), 0);
        assertEq(sdTokenGauge.balanceOf(alice), 0);

        vm.startPrank(alice);
        sdToken.approve(address(converter), type(uint256).max);
        sdTokenGauge.approve(address(converter), type(uint256).max);

        vm.expectRevert(APWine2SpectraConverter.NothingToRedeem.selector);
        converter.initConvert{value: 10 ** 16}(alice, 200 gwei);
        vm.stopPrank();
    }

    function test_cantInitiateFromSidechain() public {
        deal(address(sdToken), alice, 1 ether);
        deal(address(sdTokenGauge), alice, 10 ether);
        deal(alice, 1 ether);

        // Check that alice owns tokens
        assertGt(sdToken.balanceOf(alice), 0);
        assertGt(sdTokenGauge.balanceOf(alice), 0);

        vm.chainId(2);

        vm.startPrank(alice);
        sdToken.approve(address(converter), type(uint256).max);
        sdTokenGauge.approve(address(converter), type(uint256).max);

        vm.expectRevert(APWine2SpectraConverter.WrongChain.selector);
        converter.initConvert{value: 10 ** 16}(bob, 200 gwei);
        vm.stopPrank();
    }
}
