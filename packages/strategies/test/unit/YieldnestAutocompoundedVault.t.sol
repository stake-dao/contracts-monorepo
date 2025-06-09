// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {YieldnestAutocompoundedVault} from "src/integrations/yieldnest/YieldnestAutocompoundedVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {YieldnestProtocol} from "address-book/src/YieldnestEthereum.sol";
import {MockGauge} from "test/mocks/MockGauge.sol";
import {AutocompoundedVault} from "src/AutocompoundedVault.sol";

///////////////////////////////////////////////////////////////
/// --- SETUP
///////////////////////////////////////////////////////////////

contract AutocompoundedVaultTest is Test {
    YieldnestAutocompoundedVault internal autocompoundedVault;
    address internal owner;
    address internal manager;
    IERC20 internal asset;
    string internal shareName = "Autocompounded Stake DAO YND";
    string internal shareSymbol = "asdYND";
    uint128 internal streamingPeriod = 7 days;
    MockGauge internal gauge;

    function setUp() public virtual {
        // Deploy a mock ERC20 at the expected address of the sdYND token
        deployCodeTo("MockERC20.sol", YieldnestProtocol.SDYND);
        MockERC20(YieldnestProtocol.SDYND).initialize("Stake DAO TOKEN", "sdTOKEN", 18);
        asset = IERC20(YieldnestProtocol.SDYND);
        vm.label(address(asset), "asset");

        // Deploy the mock gauge
        gauge = new MockGauge("Stake DAO sdYND Gauge ", "sdYND-gauge", 18, address(asset));
        vm.label(address(gauge), "gauge");

        // Set the owner and manager addresses
        owner = makeAddr("owner");
        manager = makeAddr("manager");

        // Deploy the Yieldnest Autocompounded Vault
        autocompoundedVault = new YieldnestAutocompoundedVault(owner, address(gauge), manager);
        vm.label(address(autocompoundedVault), "AutocompoundedVault");
    }

    /// @notice Utility function to ensure a fuzzed address has not been previously labeled
    function _assumeUnlabeledAddress(address fuzzedAddress) internal view {
        vm.assume(bytes10(bytes(vm.getLabel(fuzzedAddress))) == bytes10(bytes("unlabeled:")));
    }

    function _assumeNotPrecompiledAddress(address fuzzedAddress) internal pure {
        vm.assume(uint160(fuzzedAddress) > 100);
    }

    function _assumeSafeAddress(address fuzzedAddress) internal view {
        _assumeUnlabeledAddress(fuzzedAddress);
        _assumeNotPrecompiledAddress(fuzzedAddress);
    }
}

///////////////////////////////////////////////////////////////
/// --- TEST SCENARIOS
///////////////////////////////////////////////////////////////

contract Constructor is AutocompoundedVaultTest {
    function test_CorrectlySetsTheAsset() external view {
        // it correctly sets the asset

        assertEq(autocompoundedVault.asset(), address(asset));
    }

    function test_CorrectlySetsTheNameOfTheShares() external view {
        // it correctly sets the name of the shares

        assertEq(autocompoundedVault.name(), shareName);
    }

    function test_CorrectlySetsTheSymbolOfTheShares() external view {
        // it correctly sets the symbol of the shares

        assertEq(autocompoundedVault.symbol(), shareSymbol);
    }

    function test_CorrectlySetsTheStreamingPeriod() external view {
        // it correctly sets the streaming period

        assertEq(autocompoundedVault.STREAMING_PERIOD(), streamingPeriod);
    }

    function test_CorrectlySetsTheManager() external view {
        // it correctly sets the manager

        assertEq(autocompoundedVault.manager(), manager);
    }

    function test_CorrectlySetsTheOwner() external view {
        // it correctly sets the owner

        assertEq(autocompoundedVault.owner(), owner);
    }

    function test_CorrectlySetsTheGauge() external view {
        // it correctly sets the asset

        assertEq(address(autocompoundedVault.LIQUIDITY_GAUGE()), address(gauge));
    }

    function test_CorrectlySetsTheManagerAsTheRewardsReceiver() external view {
        // it correctly sets the manager as the rewards receiver

        assertEq(autocompoundedVault.LIQUIDITY_GAUGE().rewards_receiver(address(autocompoundedVault)), manager);
    }

    function test_CorrectlySetsTheInfiniteApprovalOnTheGauge() external view {
        // it correctly sets the infinite approval on the gauge

        assertEq(asset.allowance(address(autocompoundedVault), address(gauge)), type(uint256).max);
    }
}

contract Manager is AutocompoundedVaultTest {
    function testFuzz_SetsTheNewManagerAsTheRewardsReceiver(address newManager) external {
        // it sets the new manager

        vm.prank(owner);
        autocompoundedVault.setManager(newManager);

        assertEq(autocompoundedVault.manager(), newManager);
        assertEq(autocompoundedVault.LIQUIDITY_GAUGE().rewards_receiver(address(autocompoundedVault)), newManager);
    }
}

contract RecoverLostAssets is AutocompoundedVaultTest {
    function test_RevertsIfTheCallerIsNotTheManager() external {
        // it reverts if the caller is not the manager

        vm.expectRevert(abi.encodeWithSelector(AutocompoundedVault.InvalidManager.selector));
        autocompoundedVault.recoverLostAssets(makeAddr("receiver"), 100);
    }

    function test_RevertsIfThereIsNoAssetToRecover() external {
        // it reverts if there is no asset to recover

        vm.expectRevert(abi.encodeWithSelector(YieldnestAutocompoundedVault.NothingToRecover.selector));
        vm.prank(manager);
        autocompoundedVault.recoverLostAssets(makeAddr("receiver"), 100);
    }

    function test_RevertsIfTheAmountToRecoverIsGreaterThanTheAmountOfAsset() external {
        // it reverts if the amount to recover is greater than the amount of asset

        uint256 airdrop = 100;
        deal(address(asset), address(autocompoundedVault), airdrop);

        vm.expectRevert(abi.encodeWithSelector(YieldnestAutocompoundedVault.NotEnoughAssetToRecover.selector));
        vm.prank(manager);
        autocompoundedVault.recoverLostAssets(makeAddr("receiver"), airdrop + 1);
    }

    function test_CorrectlyRecoversTheAsset(uint256 airdrop, address receiver) external {
        // it correctly recovers the asset

        airdrop = bound(airdrop, 1e18, 1e25);

        deal(address(asset), address(this), airdrop);
        asset.transfer(address(autocompoundedVault), airdrop);

        uint256 receiverBeforeBalance = asset.balanceOf(receiver);
        asset.balanceOf(address(autocompoundedVault));

        vm.prank(manager);
        autocompoundedVault.recoverLostAssets(receiver, airdrop);

        assertEq(asset.balanceOf(receiver) - receiverBeforeBalance, airdrop);
        assertEq(asset.balanceOf(address(autocompoundedVault)), 0);
    }

    function test_EmitsAnEvent() external {
        // it emits an event

        uint256 airdrop = 1e22;
        address receiver = makeAddr("receiver");

        deal(address(asset), address(this), airdrop);
        asset.transfer(address(autocompoundedVault), airdrop);

        vm.expectEmit(true, true, true, true);
        emit YieldnestAutocompoundedVault.LostAssetsRecovered(receiver, airdrop);

        vm.prank(manager);
        autocompoundedVault.recoverLostAssets(receiver, airdrop);
    }
}
