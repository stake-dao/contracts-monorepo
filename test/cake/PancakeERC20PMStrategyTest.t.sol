// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "solady/utils/LibClone.sol";

import "address-book/dao/56.sol";
import "address-book/lockers/56.sol";

import "src/base/utils/Constants.sol";
import "src/base/interfaces/ILocker.sol";

import "src/cake/adapter/DEdgeAdapter.sol";
import "src/cake/adapter/AlpacaAdapter.sol";
import "src/cake/adapter/AdapterFactory.sol";
import "src/cake/adapter/AdapterRegistry.sol";

import "src/cake/vault/ALMDepositorVault.sol";
import "src/cake/strategy/PancakeERC20Strategy.sol";
import "src/cake/factory/PancakeVaultFactoryXChain.sol";

abstract contract PancakeERC20PMStrategyTest is Test {
    ILocker public constant locker = ILocker(CAKE.LOCKER);
    IExecutor public constant EXECUTOR = IExecutor(CAKE.EXECUTOR);
    address public constant FARM_BOOSTER = 0x5dbC7e443cCaD0bFB15a081F1A5C6BA0caB5b1E6;

    address public lpToken;
    address public wrapper;

    address public token0;
    address public token1;

    ALMDepositorVault public vault;
    ALMDepositorVault public vaultImpl;

    PancakeERC20Strategy public strategy;
    PancakeERC20Strategy public strategyImpl;

    address public rewardDistributorImpl;
    ILiquidityGaugeStrat public rewardDistributor;

    PancakeVaultFactoryXChain public factory;

    AdapterFactory public adapterFactory;
    AdapterRegistry public adapterRegistry;

    DEdgeAdapter public dEdgeAdapterImpl;
    AlpacaAdapter public alpacaAdapterImpl;

    constructor(address _lpToken, address _wrapper) {
        lpToken = _lpToken;
        wrapper = _wrapper;
    }

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("bnb"), 38_743_240);

        (address _token0, address _token1,) = _checkAdapter(wrapper);

        token0 = _token0;
        token1 = _token1;

        /// In case the wrapper isn't whitelisted yet in the Farm Booster.
        _mockWhitelist(wrapper);

        // Deploy Strategy.
        strategyImpl = new PancakeERC20Strategy(
            address(this), address(locker), address(0), address(CAKE.TOKEN), address(0), address(CAKE.EXECUTOR)
        );

        address strategyProxy = LibClone.deployERC1967(address(strategyImpl));

        strategy = PancakeERC20Strategy(payable(strategyProxy));
        strategy.initialize(address(this));

        // Deploy Vault Implentation.
        vaultImpl = new ALMDepositorVault();

        // Deploy gauge Implementation
        rewardDistributorImpl = deployBytecode(Constants.LGV4_STRAT_XCHAIN_BYTECODE, "");

        /// Deploy Adapter Registry
        adapterRegistry = new AdapterRegistry();
        adapterRegistry.setAllowed(address(this), true);

        // Deploy Factory.
        factory = new PancakeVaultFactoryXChain(
            address(strategy), address(vaultImpl), rewardDistributorImpl, address(CAKE.TOKEN), address(adapterRegistry)
        );

        // Setup Strategy.
        strategy.setFactory(address(factory));
        strategy.setFeeRewardToken(address(CAKE.TOKEN));

        strategy.updateProtocolFee(1_700); // 17%
        strategy.updateClaimIncentiveFee(100); // 1%

        // Setup Locker.
        vm.prank(DAO.GOVERNANCE);
        EXECUTOR.allowAddress(address(strategy));

        /// Setup Adapter Factory.
        adapterFactory = new AdapterFactory(address(adapterRegistry), address(strategy));

        /// Deploy Adapter Implementations.
        dEdgeAdapterImpl = new DEdgeAdapter();
        alpacaAdapterImpl = new AlpacaAdapter();

        /// Register Protocol Adapters.
        adapterFactory.setAdapterImplementation("DeFiEdge", address(dEdgeAdapterImpl));
        adapterFactory.setAdapterImplementation("Alpaca Finance", address(alpacaAdapterImpl));

        /// Allow Factory to register adapters.
        adapterRegistry.setAllowed(address(adapterFactory), true);

        // Create vault and reward distributor for gauge.
        address _vault;
        address _rewardDistributor;
        (_vault, _rewardDistributor) = factory.create(wrapper);

        vault = ALMDepositorVault(_vault);
        rewardDistributor = ILiquidityGaugeStrat(_rewardDistributor);
    }

    function test_create_invalid_gauge() external {
        vm.expectRevert(PoolFactoryXChain.INVALID_GAUGE.selector);
        factory.create(address(0xABCD));
    }

    function test_set_adapter() public {
        _mockWhitelist(wrapper);

        /// If Wrapper doesn't have adapter, it should revert.
        (address _token0,,) = _checkAdapter(wrapper);
        if (_token0 == address(0)) {
            vm.expectRevert();
            adapterFactory.deploy(address(vault));

            assertEq(adapterRegistry.getAdapter(address(vault)), address(0));
        } else {
            address adapter = adapterFactory.deploy(address(vault));

            assertEq(IAdapter(adapter).token0(), token0);
            assertEq(IAdapter(adapter).token1(), token1);
            assertEq(IAdapter(adapter).vault(), address(vault));
            assertEq(IAdapter(adapter).stakingToken(), lpToken);

            assertEq(adapterRegistry.getAdapter(address(vault)), adapter);

            /// Already deployed adapter.
            vm.expectRevert();
            adapterFactory.deploy(address(vault));
        }
    }

    function test_deposit(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 1_000_000e18);

        deal(address(vault.token()), address(this), amount);
        vault.token().approve(address(vault), amount);

        // Deposit with _doEarn = true.
        vault.deposit(address(this), amount, true);

        ERC20 token = vault.token();

        // Strategy balance
        assertEq(strategy.balanceOf(lpToken), amount);

        // Token Balances.
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(locker)), 0);
        assertEq(token.balanceOf(address(strategy)), 0);

        // User balances.
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(rewardDistributor.balanceOf(address(this)), amount);
    }

    function test_mint_and_deposit(uint256 amount0, uint256 amount1) public {
        vm.assume(amount0 > 0 && amount1 > 0);
        vm.assume(amount0 < 1_000_000e18 && amount1 < 1_000_000e18);

        address adapter = adapterRegistry.getAdapter(address(vault));
        if (adapter == address(0)) {
            vm.expectRevert(ALMDepositorVault.NO_ADAPTER.selector);
            vault.mintThenDeposit(amount0, amount1, "", address(this));
        } else {
            deal(token0, address(this), amount0);
            deal(token1, address(this), amount1);

            SafeTransferLib.safeApprove(token0, address(vault), amount0);
            SafeTransferLib.safeApprove(token1, address(vault), amount1);

            vault.mintThenDeposit(amount0, amount1, "", address(this));

            assertEq(ERC20(token0).balanceOf(address(vault)), 0);
            assertEq(ERC20(token0).balanceOf(address(adapter)), 0);

            assertEq(ERC20(token1).balanceOf(address(vault)), 0);
            assertEq(ERC20(token1).balanceOf(address(adapter)), 0);

            assertEq(ERC20(lpToken).balanceOf(address(vault)), 0);
            assertEq(ERC20(lpToken).balanceOf(address(adapter)), 0);

            assertGe(ERC20(token0).balanceOf(address(this)), 0);
            assertGe(ERC20(token1).balanceOf(address(this)), 0);
        }
    }

    function test_mint_and_deposit_with_earn(uint256 amount, uint256 amount0, uint256 amount1) public {
        vm.assume(amount0 > 0 && amount1 > 0);
        vm.assume(amount0 < 1_000_000e18 && amount1 < 1_000_000e18);

        vm.assume(amount > 0);
        vm.assume(amount < 1_000_000e18);

        address adapter = adapterRegistry.getAdapter(address(vault));
        if (adapter == address(0)) {
            vm.expectRevert(ALMDepositorVault.NO_ADAPTER.selector);
            vault.mintThenDeposit(amount0, amount1, "", address(this));
        } else {
            deal(address(vault.token()), address(this), amount);
            vault.token().approve(address(vault), amount);

            // Deposit with _doEarn = true.
            vault.deposit(address(this), amount, false);

            uint256 incentiveTokenAmount = vault.incentiveTokenAmount();

            deal(token0, address(this), amount0);
            deal(token1, address(this), amount1);

            SafeTransferLib.safeApprove(token0, address(vault), amount0);
            SafeTransferLib.safeApprove(token1, address(vault), amount1);

            vault.mintThenDeposit(amount0, amount1, "", address(this));

            assertEq(ERC20(token0).balanceOf(address(vault)), 0);
            assertEq(ERC20(token0).balanceOf(address(adapter)), 0);

            assertEq(ERC20(token1).balanceOf(address(vault)), 0);
            assertEq(ERC20(token1).balanceOf(address(adapter)), 0);

            assertEq(ERC20(lpToken).balanceOf(address(vault)), 0);
            assertEq(ERC20(lpToken).balanceOf(address(adapter)), 0);

            assertGe(ERC20(token0).balanceOf(address(this)), 0);
            assertGe(ERC20(token1).balanceOf(address(this)), 0);

            assertGe(rewardDistributor.balanceOf(address(this)), incentiveTokenAmount);
        }
    }

    function test_withdraw_and_burn(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 1_000_000e18);

        deal(address(vault.token()), address(this), amount);
        vault.token().approve(address(vault), amount);

        // Deposit with _doEarn = true.
        vault.deposit(address(this), amount, true);

        address adapter = adapterRegistry.getAdapter(address(vault));
        if (adapter == address(0)) {
            vm.expectRevert(ALMDepositorVault.NO_ADAPTER.selector);
            vault.withdrawThenBurn(amount, "", address(this));
        } else {
            vault.withdrawThenBurn(amount, "", address(this));

            assertEq(vault.totalSupply(), 0);
            assertEq(vault.balanceOf(address(this)), 0);
            assertEq(rewardDistributor.balanceOf(address(this)), 0);

            assertGt(ERC20(token0).balanceOf(address(this)), 0);
            assertGt(ERC20(token1).balanceOf(address(this)), 0);
            assertApproxEqRel(ERC20(lpToken).balanceOf(address(this)), 0, 1e16);

            assertEq(ERC20(token0).balanceOf(address(vault)), 0);
            assertEq(ERC20(token0).balanceOf(address(adapter)), 0);

            assertEq(ERC20(token1).balanceOf(address(vault)), 0);
            assertEq(ERC20(token1).balanceOf(address(adapter)), 0);

            assertEq(ERC20(lpToken).balanceOf(address(vault)), 0);
            assertEq(ERC20(lpToken).balanceOf(address(adapter)), 0);
        }
    }

    function test_withdraw(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 1_000_000e18);

        deal(address(vault.token()), address(this), amount);
        vault.token().approve(address(vault), amount);

        // Deposit with _doEarn = true.
        vault.deposit(address(this), amount, true);

        ERC20 token = vault.token();

        // Withdraw.
        vault.withdraw(amount);

        // Token Balances.
        assertEq(token.balanceOf(address(locker)), 0);
        assertEq(token.balanceOf(address(strategy)), 0);
        assertEq(token.balanceOf(address(this)), amount);

        // Strategy Balances.
        assertEq(strategy.balanceOf(lpToken), 0);

        // User balances.
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(rewardDistributor.balanceOf(address(this)), 0);
    }

    function test_harvest(uint256 amount, uint256 harvestReward) public {
        _mockWhitelist(wrapper);

        vm.assume(amount > 100e18);
        vm.assume(amount < 1_000_000e18);

        vm.assume(harvestReward > 1000e18);
        vm.assume(harvestReward < 1_000_000e18);

        _distributeRewards(harvestReward);

        deal(address(vault.token()), address(this), amount);
        vault.token().approve(address(vault), amount);

        // Deposit with _doEarn = true.
        vault.deposit(address(this), amount, true);

        skip(1 days);

        assertGe(_balanceOf(CAKE.TOKEN, address(wrapper)), harvestReward);

        assertEq(_balanceOf(CAKE.TOKEN, address(this)), 0);
        assertEq(_balanceOf(CAKE.TOKEN, address(strategy)), 0);
        assertEq(_balanceOf(CAKE.TOKEN, address(rewardDistributor)), 0);

        assertEq(strategy.feesAccrued(), 0);

        strategy.harvest(address(vault.token()), false, false);

        uint256 rewardDistributorBalance = _balanceOf(CAKE.TOKEN, address(rewardDistributor));
        uint256 feeAccrued = _balanceOf(CAKE.TOKEN, address(strategy));
        uint256 harvesterReward = _balanceOf(CAKE.TOKEN, address(this));
        uint256 totalHarvested = rewardDistributorBalance + feeAccrued + harvesterReward;

        assertGt(harvesterReward, 0);
        assertGt(rewardDistributorBalance, 0);
        assertEq(feeAccrued, strategy.feesAccrued());

        assertEq(totalHarvested * strategy.protocolFeesPercent() / strategy.DENOMINATOR(), feeAccrued);
        assertEq(totalHarvested * strategy.claimIncentiveFee() / strategy.DENOMINATOR(), harvesterReward);
    }

    //////////////////////////////////////////////////////
    /// --- HELPER UTILS ---
    //////////////////////////////////////////////////////

    function _mockWhitelist(address _wrapper) internal {
        vm.mockCall(
            FARM_BOOSTER, abi.encodeWithSelector(ICakeFarmBooster.whiteListWrapper.selector, _wrapper), abi.encode(true)
        );
    }

    function _distributeRewards(uint256 amount) internal {
        address owner = ICakeV2Wrapper(wrapper).owner();

        vm.startPrank(owner);

        deal(CAKE.TOKEN, address(owner), amount);
        SafeTransferLib.safeTransfer(CAKE.TOKEN, address(wrapper), amount);

        uint256 endTimestamp = ICakeV2Wrapper(wrapper).endTimestamp();

        if (endTimestamp < block.timestamp) {
            ICakeV2Wrapper(wrapper).restart(block.timestamp, block.timestamp + 4 weeks, amount / 4 weeks);
        }

        vm.stopPrank();
    }

    function _checkAdapter(address _wrapper) internal returns (address _token0, address _token1, address adapter) {
        try ICakeV2Wrapper(_wrapper).adapterAddr() returns (address _adapter) {
            adapter = _adapter;

            _token0 = IAdapter(_adapter).token0();
            _token1 = IAdapter(_adapter).token1();
        } catch {
            return (address(0), address(0), address(0));
        }
    }

    function _balanceOf(address _token, address _account) internal view returns (uint256) {
        return ERC20(_token).balanceOf(_account);
    }

    function deployBytecode(bytes memory bytecode, bytes memory args) private returns (address deployed) {
        bytecode = abi.encodePacked(bytecode, args);

        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        require(deployed != address(0), "DEPLOYMENT_FAILED");
    }
}
