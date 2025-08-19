// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IStandardizedYield} from "@pendle/v2-sy/../interfaces/IStandardizedYield.sol";
import {SYASDPENDLE} from "src/integrations/pendle/SYASDPENDLE.sol";
import {PendleLocker} from "@address-book/src/PendleEthereum.sol";
import {SYASDPENDLEAdapter} from "src/integrations/pendle/SYASDPENDLEAdapter.sol";
import {SYASDPENDLETest} from "test/fork/pendle/SYASDPENDLE.t.sol";
import {PendleERC4626WithAdapterSY} from
    "@pendle/v2-sy/StandardizedYield/implementations/Adapter/extensions/PendleERC4626WithAdapterSY.sol";

interface IProxyAdmin {
    function owner() external view returns (address);
    function upgradeAndCall(address proxy, address implementation, bytes memory data) external;
}

/// @notice This test is used to test the migration of the SYASPENDLE contract
///         to the SYASDPENDLEAdapter variant.
contract SYASDPENDLEAdapterTest is SYASDPENDLETest {
    IProxyAdmin internal constant PROXY_ADMIN = IProxyAdmin(0xA28c08f165116587D4F3E708743B4dEe155c5E64);

    function setUp() public override {
        super.setUp();

        vm.label(address(PROXY_ADMIN), "ProxyAdmin");
    }

    ///////////////////////////////////////////////////////////////
    // --- UTILS
    ///////////////////////////////////////////////////////////////

    function _setUpFork() internal override {
        vm.createSelectFork("mainnet", 23_124_262);
    }

    function _deploySY() internal override returns (IStandardizedYield _sy) {
        vm.startPrank(deployer);
        address adapter = address(new SYASDPENDLEAdapter());
        address syNewImplementation = address(new PendleERC4626WithAdapterSY(PendleLocker.ASDTOKEN));
        vm.stopPrank();

        _upgradeExistingProxy(PendleLocker.SYASDTOKEN, syNewImplementation);

        vm.startPrank(IProxyAdmin(PendleLocker.SYASDTOKEN).owner());
        PendleERC4626WithAdapterSY(payable(PendleLocker.SYASDTOKEN)).setAdapter(adapter);
        vm.stopPrank();

        _sy = IStandardizedYield(PendleLocker.SYASDTOKEN);
    }

    function _upgradeExistingProxy(address proxy, address newImplementation) internal virtual {
        vm.startPrank(PROXY_ADMIN.owner());
        PROXY_ADMIN.upgradeAndCall(proxy, newImplementation, "");
        vm.stopPrank();
    }

    function _getExpectedSyReceived(address tokenIn, uint256 amountIn)
        internal
        view
        override
        returns (uint256 expectedSYOut)
    {
        if (tokenIn == PendleLocker.TOKEN) expectedSYOut = sy.previewDeposit(tokenIn, amountIn);
        else return super._getExpectedSyReceived(tokenIn, amountIn);
    }

    ///////////////////////////////////////////////////////////////
    // --- TESTS
    ///////////////////////////////////////////////////////////////

    function test_token_exchangeRate() public view override {
        // @dev: initial exchange rate on the block 23124262
        assertEq(sy.exchangeRate(), 1_063_920_148_768_376_544);
    }

    function test_metadata_getTokensIn() public view override {
        address[] memory tokens = sy.getTokensIn();
        // Take into account the extra Pendle token supported by the adapter
        assertEq(tokens.length, 3);
        assertEq(tokens[0], PendleLocker.TOKEN);
        assertEq(tokens[1], PendleLocker.SDTOKEN);
        assertEq(tokens[2], PendleLocker.ASDTOKEN);
    }
}
