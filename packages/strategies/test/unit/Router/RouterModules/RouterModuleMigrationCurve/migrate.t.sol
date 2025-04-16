// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address, Errors} from "@openzeppelin/contracts/utils/Address.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {RouterModuleMigrationCurve} from "src/RouterModules/RouterModuleMigrationCurve.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {RouterModulesTest} from "test/unit/Router/RouterModules/RouterModulesTest.t.sol";

contract RouterModuleMigrationCurve__migrate is RouterModulesTest {
    RouterModuleMigrationCurve internal module;
    MockCurveLiquidityGauge internal from;

    function setUp() public virtual override {
        super.setUp();

        module = new RouterModuleMigrationCurve();
        _cheat_setModule(uint8(4), address(module));
    }

    function test_RevertsIfCalledByUnauthorizedAddress(bytes32 randomNonce) external {
        // it reverts if called by unauthorized address

        IncorrectFakeRouter incorrectFakeRouter = new IncorrectFakeRouter{salt: randomNonce}();
        vm.assume(address(incorrectFakeRouter) != address(router));

        vm.expectRevert(abi.encodeWithSelector(Errors.FailedCall.selector));
        incorrectFakeRouter.execute(address(module));
    }

    function test_RevertsIfTheFromAndToDoesntHaveTheSameToken(address fromToken, address toToken) external {
        // it reverts if the from and to doesn't have the same token

        vm.assume(fromToken != toToken);

        from = new MockCurveLiquidityGauge(fromToken);
        address to = address(new MockIERC4626());

        vm.mockCall(
            address(from), abi.encodeWithSelector(MockCurveLiquidityGauge.lp_token.selector), abi.encode(fromToken)
        );
        vm.mockCall(address(to), abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(toToken));

        vm.expectRevert(abi.encodeWithSelector(RouterModuleMigrationCurve.VaultNotCompatible.selector));
        module.migrate(address(from), to, address(0), 100);
    }

    function test_MigratesTheTokenFromTheLiquidityGaugeToTheRewardVault(address account, uint256 amount) external {
        // it migrates the token from the liquidity gauge to the reward vault

        // validate the fuzzed account address
        vm.assume(account != address(0));
        _assumeUnlabeledAddress(account);
        vm.label({account: account, newLabel: "account"});

        // validate the fuzzed shares amount
        vm.assume(amount > 0);

        // deploy the asset expected as an input to both vault
        asset = address(new ERC20Mock("Asset", "ASSET", 18));
        vm.label({account: asset, newLabel: "asset"});

        // deploy the mock vault ("from")
        from = new MockCurveLiquidityGauge(asset);
        vm.label({account: address(from), newLabel: "Curve Liquidity Gauge"});

        // set the owner balance of asset and mint the shares
        deal(asset, account, amount);
        vm.prank(account);
        ERC20Mock(asset).approve(address(from), amount);
        vm.prank(account);
        from.deposit(amount);

        // assert the initial balances have the expected values
        assertEq(ERC20Mock(asset).balanceOf(account), 0);
        assertEq(from.balanceOf(account), amount);

        // migrate the token
        _test_token_migration(account, amount);
    }

    function _test_token_migration(address account, uint256 amount)
        internal
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it migrates the token from the liquidity gauge to the reward vault

        // clone the harnessed reward vault with the new immutable variables
        cloneRewardVault = RewardVaultHarness(
            Clones.cloneWithImmutableArgs(address(rewardVaultHarness), abi.encodePacked(gauge, asset))
        );
        vm.label({account: address(cloneRewardVault), newLabel: "cloneRewardVault"});

        // approve the balance of shares for the router
        vm.prank(account);
        from.approve(address(router), amount);

        // mock the dependencies needed for the deposit function flow
        (, IStrategy.PendingRewards memory pendingRewards) = _mock_test_dependencies(amount);

        // expect the checkpoint to be called with the account as the recipient
        vm.expectCall(
            address(accountant),
            abi.encodeWithSelector(
                bytes4(keccak256("checkpoint(address,address,address,uint128,(uint128,uint128),bool,address)")),
                gauge,
                address(0),
                account,
                uint128(amount),
                pendingRewards,
                false,
                address(0)
            ),
            1
        );

        // mock `Registry.allowed()` to authorize the router to call the deposit function of the reward vault
        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(
                IProtocolController.allowed.selector,
                address(cloneRewardVault),
                address(router),
                bytes4(keccak256("deposit(address,uint256)"))
            ),
            abi.encode(true)
        );

        // Construct the data to call the deposit router module
        bytes memory dataModule = bytes.concat(
            bytes1(uint8(4)),
            abi.encodeWithSelector(
                bytes4(keccak256("migrate(address,address,address,uint256)")),
                address(from),
                address(cloneRewardVault),
                account,
                amount
            )
        );
        bytes[] memory calls = new bytes[](1);
        calls[0] = dataModule;

        // execute the calls as the router owner
        vm.prank(routerOwner);
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(address(router), account, amount, amount);
        router.execute(calls);

        assertEq(ERC20Mock(asset).balanceOf(account), 0);
        assertEq(ERC20Mock(asset).balanceOf(address(module)), 0);
    }
}

contract IncorrectFakeRouter {
    function execute(address module) external returns (bytes memory) {
        // construct the valid data for calling the module
        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256("migrate(address,address,address,uint256)")), address(399), address(499), address(599), 100
        );

        return Address.functionDelegateCall(module, data);
    }
}

contract MockCurveLiquidityGauge is ERC20Mock {
    address private lpToken;

    constructor(address _lpToken) ERC20Mock("MockCurveLiquidityGauge", "MLG", 18) {
        lpToken = _lpToken;
    }

    function lp_token() external view returns (address) {
        return lpToken;
    }

    function deposit(uint256 asset) external {
        IERC20(lpToken).transferFrom(msg.sender, address(this), asset);
        _mint(msg.sender, asset);
    }

    function withdraw(uint256 shares) external {
        _burn(msg.sender, shares);
        IERC20(lpToken).transfer(msg.sender, shares);
    }
}

contract MockIERC4626 {
    function asset() external view returns (address) {}
    function deposit(address account, uint256 assets) external returns (uint256) {}
}
