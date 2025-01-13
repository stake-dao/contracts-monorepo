// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import {BaseZeroLendTest} from "test/linea/zerolend/common/BaseZeroLendTest.sol";

import "src/linea/zerolend/zero/Accumulator.sol";
import {sdToken as SdToken} from "src/common/token/sdToken.sol";
import {Locker} from "src/linea/zerolend/zero/Locker.sol";
import {Depositor} from "src/linea/zerolend/zero/Depositor.sol";

import {IStrategy} from "herdaddy/interfaces/stake-dao/IStrategy.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {IDepositor} from "src/common/interfaces/IDepositor.sol";
import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";

// end to end tests for the ZeroLend integration
abstract contract BaseZeroLendTokenTest is BaseZeroLendTest {
    address zeroLockerToken = 0x08D5FEA625B1dBf9Bae0b97437303a0374ee02F8;
    ERC20 zeroToken = ERC20(0x78354f8DcCB269a615A7e0a24f9B0718FDC3C7A7);
    ERC20 veZero = ERC20(0xf374229a18ff691406f99CCBD93e8a3f16B68888);

    address zeroTokenHolder = 0xA05D8213472620292D4D96DCDA2Dd5dB4B65df2f;

    constructor() {}

    function _createLabels() internal {
        vm.label(address(zeroToken), "ZeroLend");
        vm.label(address(veZero), "veZero");
        vm.label(zeroLockerToken, "Locked ZERO Tokens (T-ZERO)");
        vm.label(0xb320Fa6C84d67145759f2e6B06e2Fc14B0BADb5d, "OmnichainStakingToken impl.");
        vm.label(0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f, "WETH");
    }

    function _deployZeroIntegration() internal {
        _createLabels();

        sdToken = _deploySdZero();
        liquidityGauge = ILiquidityGauge(_deployLiquidityGauge(sdToken));
        locker = _deployLocker();
        accumulator = BaseAccumulator(payable(_deployAccumulator()));
        depositor = IDepositor(_deployDepositor());

        _getSomeZeroTokens(address(this));
        _setupContractGovernance();
    }

    function _getSomeZeroTokens(address _account) internal {
        vm.prank(zeroTokenHolder);
        zeroToken.transfer(_account, 1_000_000 ether);
    }

    function _deploySdZero() internal returns (address _sdZero) {
        _sdZero = address((new SdToken("Stake DAO ZeroLend", "sdZero")));
    }

    function _deployLocker() internal returns (address _locker) {
        // TODO change governance to the actual stake DAO governance
        _locker = address(new Locker(zeroLockerToken, address(this), address(zeroToken), address(veZero)));
    }

    function _deployAccumulator() internal virtual returns (address payable _accumulator) {
        _accumulator = payable(address(new Accumulator(address(liquidityGauge), locker, address(this))));

        /// Set up the accumulator in the locker.
        vm.prank(ILocker(locker).governance());
        ILocker(locker).setAccumulator(address(accumulator));
    }

    function _deployDepositor() internal returns (address _depositor) {
        _depositor = address(new Depositor(address(zeroToken), locker, sdToken, address(liquidityGauge)));
    }

    function _createInitialLock() internal {
        // we need to initialize the ERC721 token locking
        zeroToken.transfer(locker, 1);
        ILocker(locker).createLock(1, 4 * 365 days);
    }

    function _setupContractGovernance() internal {
        ISdToken(sdToken).setOperator(address(depositor));
        ILocker(locker).setDepositor(address(depositor));
        ILocker(locker).setAccumulator(address(accumulator));

        _createInitialLock();

        liquidityGauge.add_reward(address(zeroToken), address(accumulator));
    }
}
