// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address, Errors} from "@openzeppelin/contracts/utils/Address.sol";
import {Address, Errors} from "@openzeppelin/contracts/utils/Address.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {RouterModuleMigrationStakeDAOV1, IVault} from "src/RouterModules/RouterModuleMigrationStakeDAOV1.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {RouterModulesTest} from "test/unit/Router/RouterModules/RouterModulesTest.t.sol";

contract RouterModuleMigrationStakeDAOV1__migrate is RouterModulesTest {
    RouterModuleMigrationStakeDAOV1 internal module;
    MockVault internal from;

    function setUp() public virtual override {
        super.setUp();

        module = new RouterModuleMigrationStakeDAOV1();
        _cheat_setModule(uint8(4), address(module));
    }

    function test_RevertsIfUsedDirectly(bytes32 randomNonce) external {
        // it reverts if used directly

        IncorrectFakeRouter incorrectFakeRouter = new IncorrectFakeRouter{salt: randomNonce}();
        vm.assume(address(incorrectFakeRouter) != address(router));

        vm.expectRevert(abi.encodeWithSelector(Errors.FailedCall.selector));
        incorrectFakeRouter.execute(address(module));
    }

    function test_RevertsIfTheFromAndToDoesntHaveTheSameToken(address fromToken, address toToken) external {
        // it reverts if the from and to doesn't have the same token

        vm.assume(fromToken != toToken);

        from = new MockVault(fromToken);
        address to = address(new MockIERC4626());

        vm.mockCall(address(from), abi.encodeWithSelector(IVault.token.selector), abi.encode(fromToken));
        vm.mockCall(address(to), abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(toToken));

        vm.expectRevert(abi.encodeWithSelector(RouterModuleMigrationStakeDAOV1.VaultNotCompatible.selector));
        module.migrate(address(from), to, address(0), 100);
    }

    function test_MigratesTheTokenFromTheVaultToTheRewardVault(address account, uint256 amount) external {
        // it migrates the token from the vault to the reward vault

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
        from = new MockVault(asset);
        vm.label({account: address(from), newLabel: "from"});

        // deploy the strategy's asset mock
        strategyAsset = address(new ERC20Mock("Strategy Asset", "STRAT", 18));
        vm.label({account: strategyAsset, newLabel: "strategyAsset"});

        // set the owner balance of asset and mint the shares
        deal(asset, account, amount);
        vm.prank(account);
        ERC20Mock(asset).approve(address(from), amount);
        vm.prank(account);
        from.deposit(amount);

        // assert the initial balances have the expected values
        assertEq(ERC20Mock(asset).balanceOf(account), 0);
        assertEq(from.balanceOf(account), amount);
        assertEq(ERC20Mock(asset).balanceOf(address(from)), amount);

        // migrate the token
        _test_token_migration(account, amount);
    }

    function _test_token_migration(address account, uint256 amount)
        internal
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // get the liquidity gauge
        MockLiquidityGauge _gauge = MockLiquidityGauge(from.liquidityGauge());

        // clone the harnessed reward vault with the new immutable variables
        cloneRewardVault = RewardVaultHarness(
            Clones.cloneWithImmutableArgs(address(rewardVaultHarness), abi.encodePacked(gauge, asset))
        );
        vm.label({account: address(cloneRewardVault), newLabel: "cloneRewardVault"});

        // approve the balance of the gauge token for the router
        vm.prank(account);
        _gauge.approve(address(router), amount);

        // mock the dependencies needed for the deposit function flow
        (, IStrategy.PendingRewards memory pendingRewards) = _mock_test_dependencies(amount);

        // expect the checkpoint to be called with the account as the recipient
        vm.expectCall(
            address(accountant),
            abi.encodeCall(IAccountant.checkpoint, (gauge, address(0), account, uint128(amount), pendingRewards, false)),
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

        assertEq(_gauge.balanceOf(account), 0);
        assertEq(_gauge.balanceOf(address(module)), 0);
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

contract MockLiquidityGauge is ERC20Mock {
    address private owner;

    constructor() ERC20Mock("Liquidity Gauge", "LIQUIDITY_GAUGE", 18) {
        owner = msg.sender;
    }

    function mintShares(address to, uint256 amount) external {
        require(msg.sender == owner, "OnlyOwner");
        _mint(to, amount);
    }

    function burnShares(address from, uint256 amount) external {
        require(msg.sender == owner, "OnlyOwner");
        _burn(from, amount);
    }
}

contract MockVault {
    address private $asset;
    MockLiquidityGauge private gauge;

    constructor(address asset) {
        gauge = new MockLiquidityGauge();
        $asset = asset;
    }

    function token() external view returns (address) {
        return $asset;
    }

    function deposit(uint256 asset) external {
        IERC4626($asset).transferFrom(msg.sender, address(this), asset);
        gauge.mintShares(msg.sender, asset);
    }

    function withdraw(uint256 shares) external {
        gauge.burnShares(msg.sender, shares);
        IERC4626($asset).transfer(msg.sender, shares);
    }

    function liquidityGauge() external view returns (address) {
        return address(gauge);
    }

    function balanceOf(address account) external view returns (uint256) {
        return gauge.balanceOf(account);
    }
}

contract MockIERC4626 {
    function asset() external view returns (address) {}
    function deposit(address account, uint256 assets) external returns (uint256) {}
}
