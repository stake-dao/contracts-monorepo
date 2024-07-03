// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/src/Test.sol";
import "solady/src/utils/LibClone.sol";

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {Yearn} from "address-book/src/protocols/1.sol";
import {YFI} from "address-book/src/lockers/1.sol";
import {DAO} from "address-book/src/dao/1.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {YearnStrategy} from "src/mainnet/yearn/strategy/YearnStrategy.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {GaugeDepositorVault} from "src/common/vault/GaugeDepositorVault.sol";
import {ILiquidityGaugeStrat} from "src/common/interfaces/ILiquidityGaugeStrat.sol";
import {YearnVaultFactory} from "src/mainnet/yearn/factory/YearnVaultFactory.sol";

abstract contract YearnStrategyTestBis is Test {
    using FixedPointMathLib for uint256;

    address public immutable gauge;

    YearnVaultFactory public factory;

    YearnStrategy public strategy;
    YearnStrategy public strategyImpl;
    GaugeDepositorVault public vaultImpl;

    GaugeDepositorVault vault;
    ILiquidityGaugeStrat rewardDistributor;

    ILocker public locker;
    address public veToken;
    address public sdtDistributor;

    address public constant DYFI = Yearn.DYFI;
    address public constant YFI_REWARD_POOL = Yearn.YFI_REWARD_POOL;
    address public constant DYFI_REWARD_POOL = Yearn.DYFI_REWARD_POOL;

    address public constant GAUGE_IMPL = 0xc1e4775B3A589784aAcD15265AC39D3B3c13Ca3c;

    address public constant claimer = address(0xBEEC);

    constructor(address _gauge) {
        gauge = _gauge;
    }

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 19_582_912);

        /// Initialize from the address book.
        veToken = Yearn.VEYFI;
        locker = ILocker(YFI.LOCKER);
        sdtDistributor = DAO.STRATEGY_SDT_DISTRIBUTOR;

        /// Deploy Strategy.
        strategyImpl = new YearnStrategy(address(this), address(locker), veToken, DYFI, YFI_REWARD_POOL);

        address strategyProxy = LibClone.deployERC1967(address(strategyImpl));

        strategy = YearnStrategy(payable(strategyProxy));
        strategy.initialize(address(this));

        /// Deploy Vault Implentation.
        vaultImpl = new GaugeDepositorVault();

        /// Deploy Factory.
        factory = new YearnVaultFactory(address(strategy), address(vaultImpl), GAUGE_IMPL);

        /// Setup Strategy.
        strategy.setFactory(address(factory));
        strategy.setAccumulator(address(0xACC)); // Fake accumulator.
        strategy.setFeeRewardToken(YFI.TOKEN);

        strategy.updateProtocolFee(1_700); // 17%
        strategy.updateClaimIncentiveFee(100); // 1%

        /// Setup Locker.
        vm.prank(locker.governance());
        locker.setGovernance(address(strategy));

        /// Create vault and reward distributor for gauge.
        address _vault;
        address _rewardDistributor;
        (_vault, _rewardDistributor) = factory.create(gauge);

        vault = GaugeDepositorVault(_vault);
        rewardDistributor = ILiquidityGaugeStrat(_rewardDistributor);
    }

    function test_deposit(uint128 _amount) public {
        uint256 amount = uint256(_amount);
        vm.assume(amount != 0);

        deal(address(vault.token()), address(this), amount);
        vault.token().approve(address(vault), amount);

        /// Deposit with _doEarn = true.
        vault.deposit(address(this), amount, true);

        ERC20 token = vault.token();

        /// Token Balances.
        assertEq(token.balanceOf(address(locker)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(strategy)), 0);

        /// Strategy Balances.
        assertEq(strategy.balanceOf(address(token)), amount);

        /// Gauge Balances.
        assertEq(ILiquidityGaugeStrat(gauge).balanceOf(address(locker)), amount);

        /// User balances.
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(rewardDistributor.balanceOf(address(this)), amount);
    }

    function test_withdraw(uint128 _amount) public {
        uint256 amount = uint256(_amount);
        vm.assume(amount != 0);

        deal(address(vault.token()), address(this), amount);
        vault.token().approve(address(vault), amount);

        /// Deposit with _doEarn = true.
        vault.deposit(address(this), amount, true);

        /// Withdraw.
        vault.withdraw(amount);

        ERC20 token = vault.token();

        /// Token Balances.
        assertEq(token.balanceOf(address(locker)), 0);
        assertEq(token.balanceOf(address(strategy)), 0);
        assertEq(token.balanceOf(address(this)), amount);

        /// Strategy Balances.
        assertEq(strategy.balanceOf(address(token)), 0);

        /// Gauge Balances.
        assertEq(ILiquidityGaugeStrat(gauge).balanceOf(address(locker)), 0);

        /// User balances.
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(rewardDistributor.balanceOf(address(this)), 0);
    }

    function test_harvest(uint128 _amount) public {
        address token = address(vault.token());
        address rewardToken = strategy.rewardToken();

        uint256 amount = uint256(_amount);
        vm.assume(amount > 1 * 10 ** ERC20(token).decimals());
        vm.assume(amount < 1_000 * 10 ** ERC20(token).decimals());

        deal(address(vault.token()), address(this), amount);
        vault.token().approve(address(vault), amount);

        /// Deposit with _doEarn = true.
        vault.deposit(address(this), amount, true);

        skip(1 days);

        uint256 _expectedLockerRewardTokenAmount = _getRewardTokenAmount();
        assertGt(_expectedLockerRewardTokenAmount, 0);

        vm.prank(claimer);
        strategy.harvest(token, false, false);

        uint256 _claimerFee;
        uint256 _protocolFee;

        /// Compute the fees.
        _protocolFee = _expectedLockerRewardTokenAmount.mulDiv(17, 100);
        _claimerFee = _expectedLockerRewardTokenAmount.mulDiv(1, 100);

        _expectedLockerRewardTokenAmount -= (_protocolFee + _claimerFee);

        assertEq(_balanceOf(rewardToken, address(claimer)), _claimerFee);

        assertEq(strategy.feesAccrued(), _protocolFee);
        assertEq(_balanceOf(rewardToken, address(strategy)), _protocolFee);

        uint256 _balanceRewardToken = _balanceOf(rewardToken, address(rewardDistributor));
        assertEq(_balanceRewardToken, _expectedLockerRewardTokenAmount);

        skip(1 days);

        uint256 _newExpectedRewardAmount = _getRewardTokenAmount();
        assertGt(_newExpectedRewardAmount, 0);

        vm.prank(claimer);
        strategy.harvest(token, false, false);

        uint256 _cumulativeProtocolFee = _protocolFee;
        uint256 _cumulativeClaimerFee = _claimerFee;

        /// Compute the fees.
        _protocolFee = _newExpectedRewardAmount.mulDiv(17, 100);
        _claimerFee = _newExpectedRewardAmount.mulDiv(1, 100);

        _cumulativeProtocolFee += _protocolFee;
        _cumulativeClaimerFee += _claimerFee;

        _newExpectedRewardAmount -= (_protocolFee + _claimerFee);

        assertEq(_balanceOf(rewardToken, address(claimer)), _cumulativeClaimerFee);

        assertEq(strategy.feesAccrued(), _cumulativeProtocolFee);
        assertEq(_balanceOf(rewardToken, address(strategy)), _cumulativeProtocolFee);

        _balanceRewardToken = _balanceOf(rewardToken, address(rewardDistributor));
        assertEq(_balanceRewardToken, _expectedLockerRewardTokenAmount + _newExpectedRewardAmount);
    }

    function _getRewardTokenAmount() internal view returns (uint256) {
        return ILiquidityGaugeStrat(gauge).earned(address(strategy.locker()));
    }

    function _balanceOf(address _token, address account) internal view returns (uint256) {
        if (_token == address(0)) {
            return account.balance;
        }

        return ERC20(_token).balanceOf(account);
    }
}
