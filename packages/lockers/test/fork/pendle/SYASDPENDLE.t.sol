// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {console} from "forge-std/src/Test.sol";
import {IERC4626} from "@pendle/v2-sy/StandardizedYield/implementations/PendleERC4626SYV2.sol";
import {IStandardizedYield} from "@pendle/v2-sy/../interfaces/IStandardizedYield.sol";
import {PendleLocker} from "@address-book/src/PendleEthereum.sol";
import {SYASDPENDLE} from "src/integrations/pendle/SYASDPENDLE.sol";
import {PMath} from "@pendle/v2-sy/libraries/math/PMath.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {BaseTest} from "test/BaseTest.t.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

abstract contract SYTestFoundation is BaseTest {
    address public deployer;
    address[] public wallets;

    IStandardizedYield public sy;
    address public startToken;

    function setUp() public virtual {
        deployer = makeAddr("deployer");

        wallets.push(makeAddr("alice"));
        wallets.push(makeAddr("bob"));
        wallets.push(makeAddr("charlie"));
        wallets.push(makeAddr("david"));
        wallets.push(makeAddr("eve"));

        _setUpFork();
        sy = _deploySY();

        vm.label(address(sy), "SYASD");
        vm.label(asdToken(), "ASDTOKEN");
        vm.label(sdToken(), "SDTOKEN");
        startToken = IERC4626(asdToken()).asset();
    }

    function _setUpFork() internal virtual {
        vm.createSelectFork("mainnet", 22_717_485);
    }

    function _deploySY() internal virtual returns (IStandardizedYield _sy) {
        vm.startPrank(deployer);

        address syImplementation = address(new SYASDPENDLE());
        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256("initialize(string,string)")),
            "", // name - unused
            "" // symbol - unused
        );
        _sy = IStandardizedYield(address(new TransparentUpgradeableProxy(syImplementation, makeAddr("admin"), data)));
        vm.stopPrank();
    }

    function refAmountFor(address token) internal view virtual returns (uint256) {
        if (token == NATIVE) return 1 ether;
        else return 10 ** IERC20Metadata(token).decimals();
    }

    function deposit(address wallet, address tokenIn, uint256 amountTokenIn)
        internal
        virtual
        returns (uint256 amountSharesOut)
    {
        if (tokenIn == NATIVE) {
            vm.prank(wallet);
            amountSharesOut = sy.deposit{value: amountTokenIn}(wallet, tokenIn, amountTokenIn, 0);
        } else {
            vm.prank(wallet);
            IERC20(tokenIn).approve(address(sy), amountTokenIn);

            vm.prank(wallet);
            amountSharesOut = sy.deposit(wallet, tokenIn, amountTokenIn, 0);
        }
    }

    function redeem(address wallet, address tokenOut, uint256 amountSharesIn)
        internal
        virtual
        returns (uint256 amountTokenOut)
    {
        vm.prank(wallet);
        amountTokenOut = sy.redeem(wallet, amountSharesIn, tokenOut, 0, false);
    }

    function sdToken() public pure virtual returns (address) {
        return PendleLocker.SDTOKEN;
    }

    function asdToken() public pure virtual returns (address) {
        return PendleLocker.ASDTOKEN;
    }
}

abstract contract DepositRedeemTest is SYTestFoundation {
    using PMath for uint256;

    function test_depositRedeem_exchangeRate() public {
        uint256 snapshot = vm.snapshotState();

        address[] memory tokensIn = getTokensInForDepositRedeemTest();
        for (uint256 k = 0; k < tokensIn.length; ++k) {
            vm.revertToState(snapshot);

            address tokenIn = tokensIn[k];

            uint256 n = wallets.length;
            uint256 refAmount = refAmountFor(tokenIn);
            for (uint256 i = 0; i < n; ++i) {
                uint256 expectedSyBalance = _getExpectedSyReceived(tokenIn, refAmount);

                fundToken(wallets[i], tokenIn, refAmount);
                deposit(wallets[i], tokenIn, refAmount);
                assertApproxEqRel(sy.balanceOf(wallets[i]), expectedSyBalance, 1e8);
            }
        }
    }

    //////////////////////////////////////////////////////
    // --- VIRTUALS
    //////////////////////////////////////////////////////
    function getTokensInForDepositRedeemTest() internal view virtual returns (address[] memory);
    function _getExpectedSyReceived(address tokenIn, uint256 amountIn) internal view virtual returns (uint256);
}

abstract contract MetadataTest is SYTestFoundation {
    function test_metadata_isValidTokenIn() public view virtual {
        address[] memory tokens = sy.getTokensIn();
        for (uint256 i = 0; i < tokens.length; ++i) {
            assertTrue(sy.isValidTokenIn(tokens[i]));
        }
        assertFalse(sy.isValidTokenIn(vm.addr(123456)));
    }

    function test_metadata_isValidTokenOut() public view virtual {
        address[] memory tokens = sy.getTokensOut();
        for (uint256 i = 0; i < tokens.length; ++i) {
            assertTrue(sy.isValidTokenOut(tokens[i]));
        }
        assertFalse(sy.isValidTokenOut(vm.addr(123456)));
    }

    //////////////////////////////////////////////////////
    // --- VIRTUALS
    //////////////////////////////////////////////////////
    function test_metadata_getTokensIn() public view virtual {}
    function test_metadata_getTokensOut() public view virtual {}
    function test_metadata_getRewardTokens() public view virtual {}
    function test_metadata_assetInfo() public view virtual {}
}

abstract contract PreviewTest is SYTestFoundation {
    uint256 internal constant DENOM = 17;
    uint256 internal constant NUMER = 3;
    uint256 internal constant NUM_TESTS = 20;

    function test_preview_depositThenRedeem() public {
        address[] memory allTokensIn = getTokensInForPreviewTest();
        address[] memory allTokensOut = getTokensOutForPreviewTest();

        address alice = wallets[0];

        uint256 divBy = 1;

        for (uint256 it = 0; it < NUM_TESTS; ++it) {
            address tokenIn = allTokensIn[it % allTokensIn.length];
            address tokenOut = allTokensOut[(it + 1) % allTokensOut.length];
            uint256 amountIn = refAmountFor(tokenIn) / divBy;

            console.log("Testing ", getSymbol(tokenIn), "=>", getSymbol(tokenOut));
            console.log("Amount in :", amountIn);

            fundToken(alice, tokenIn, amountIn);

            uint256 amountOut = _executePreviewTest(alice, tokenIn, amountIn, tokenOut, true);
            console.log("Amount out:", amountOut);
            console.log("");

            divBy = (divBy * NUMER) % DENOM;
        }
    }

    function _executePreviewTest(
        address wallet,
        address tokenIn,
        uint256 netTokenIn,
        address tokenOut,
        bool inFirstExecution
    ) private returns (uint256) {
        uint256 depositIn = netTokenIn / 2;
        for (uint256 i = 0; i < 2; ++i) {
            uint256 balanceBefore = sy.balanceOf(wallet);

            uint256 preview = sy.previewDeposit(tokenIn, depositIn);
            uint256 actual = deposit(wallet, tokenIn, depositIn);
            uint256 earning = sy.balanceOf(wallet) - balanceBefore;

            assertEq(earning, actual, "previewDeposit: actual != earning");
            assertEq(preview, actual, "previewDeposit: preview != actual");
        }

        uint256 redeemIn = sy.balanceOf(wallet) / 2;
        uint256 totalAmountOut = 0;
        for (uint256 i = 0; i < 2; ++i) {
            uint256 balanceBefore = getBalance(wallet, tokenOut);

            uint256 preview = sy.previewRedeem(tokenOut, redeemIn);
            uint256 actual = redeem(wallet, tokenOut, redeemIn);
            uint256 earning = getBalance(wallet, tokenOut) - balanceBefore;

            assertEq(earning, actual, "previewRedeem: actual != earning");
            assertEq(preview, actual, "previewRedeem: preview != actual");

            totalAmountOut += actual;
        }

        if (inFirstExecution && sy.isValidTokenIn(tokenOut) && sy.isValidTokenOut(tokenIn)) {
            uint256 amountRoundTrip = _executePreviewTest(wallet, tokenOut, totalAmountOut, tokenIn, false);

            uint256 delta = (amountRoundTrip > netTokenIn) ? amountRoundTrip - netTokenIn : netTokenIn - amountRoundTrip;

            assertLt(delta, 10, "Amount round trip should be close to netTokenIn");
        }

        return totalAmountOut;
    }

    function getTokensInForPreviewTest() internal view virtual returns (address[] memory) {
        return sy.getTokensIn();
    }

    function getTokensOutForPreviewTest() internal view virtual returns (address[] memory) {
        return sy.getTokensOut();
    }
}

contract SYASDPENDLETest is DepositRedeemTest, MetadataTest, PreviewTest {
    //////////////////////////////////////////////////////
    // --- TESTS
    //////////////////////////////////////////////////////

    function test_token_exchangeRate() public view virtual {
        // @dev: initial exchange rate on the block 22717485
        assertEq(sy.exchangeRate(), 1_030_314_074_784_136_540);
    }

    function test_metadata_getTokensIn() public view virtual override {
        address[] memory tokens = sy.getTokensIn();
        assertEq(tokens.length, 2);
        assertNotEq(tokens[0], tokens[1]);
        assertTrue(tokens[0] == asdToken() || tokens[0] == sdToken());
        assertTrue(tokens[1] == asdToken() || tokens[1] == sdToken());
    }

    function test_metadata_getTokensOut() public view override {
        address[] memory tokens = sy.getTokensOut();
        assertEq(tokens.length, 2);
        assertNotEq(tokens[0], tokens[1]);
        assertTrue(tokens[0] == asdToken() || tokens[0] == sdToken());
        assertTrue(tokens[1] == asdToken() || tokens[1] == sdToken());
    }

    function test_metadata_getRewardTokens() public view override {
        address[] memory tokens = sy.getRewardTokens();
        assertEq(tokens.length, 0);
    }

    function test_metadata_assetInfo() public view override {
        (IStandardizedYield.AssetType assetType, address assetAddress, uint8 assetDecimals) = sy.assetInfo();

        assertEq(uint256(assetType), uint256(IStandardizedYield.AssetType.TOKEN));
        assertEq(assetAddress, sdToken());
        assertEq(assetDecimals, 18);
    }

    //////////////////////////////////////////////////////
    // --- UTILS
    //////////////////////////////////////////////////////

    function getTokensInForDepositRedeemTest() internal view override returns (address[] memory) {
        return sy.getTokensIn();
    }

    function _getExpectedSyReceived(address tokenIn, uint256 amountIn)
        internal
        view
        virtual
        override
        returns (uint256 expectedSYOut)
    {
        if (tokenIn == asdToken()) expectedSYOut = amountIn;
        else if (tokenIn == sdToken()) expectedSYOut = sy.previewDeposit(tokenIn, amountIn);
        else revert("UNEXPECTED_TOKEN_IN");
    }
}
