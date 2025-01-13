// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import {BaseZeroLendTest} from "test/linea/zerolend/common/BaseZeroLendTest.sol";

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {sdToken as SdToken} from "src/common/token/sdToken.sol";
import {Locker} from "src/linea/zerolend/zerolp/Locker.sol";
import {Depositor} from "src/linea/zerolend/zerolp/Depositor.sol";
import {Accumulator} from "src/linea/zerolend/zerolp/Accumulator.sol";

import {IStrategy} from "herdaddy/interfaces/stake-dao/IStrategy.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {IDepositor} from "src/common/interfaces/IDepositor.sol";

// end to end tests for the ZeroLend integration
abstract contract BaseZeroLendLpTest is BaseZeroLendTest {
    address zeroLockerLp = 0x8bB8B092f3f872a887F377f73719c665Dd20Ab06;
    ERC20 zeroLpToken = ERC20(0x0040F36784dDA0821E74BA67f86E084D70d67a3A);
    ERC20 veZeroLp = ERC20(0x0374ae8e866723ADAE4A62DcE376129F292369b4);

    address zeroLpTokenHolder = 0x39978cc40e2D1d7E127050bDFFFBB0dFcfaEbAd0;

    constructor() {}

    function _createLabels() internal {
        vm.label(address(zeroLpToken), "ZEROlp");
        vm.label(address(veZeroLp), "veZeroLp");
        vm.label(zeroLockerLp, "zeroLockerLp");
        vm.label(0xe98f5d40f5F07376675542F9a449c59f18275A19, "OmnichainStakingLP impl.");

        vm.label(0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f, "WETH");
    }

    function _deployZeroLpIntegration() internal {
        _createLabels();

        sdToken = _deploySdZeroLp();
        liquidityGauge = ILiquidityGauge(_deployLiquidityGauge(sdToken));
        locker = _deployLpLocker();
        accumulator = BaseAccumulator(_deployAccumulator());
        depositor = IDepositor(_deployLpDepositor());

        _getSomeZeroLpTokens(address(this));
        _setupLpContractGovernance();
    }

    function _getSomeZeroLpTokens(address _account) internal {
        vm.prank(zeroLpTokenHolder);
        zeroLpToken.transfer(_account, 10 ether);
    }

    function _deploySdZeroLp() internal returns (address _sdZeroLp) {
        // TODO validate the names
        _sdZeroLp = address((new SdToken("Stake DAO ZeroLend LP", "sdZeroLp")));
    }

    function _deployLpLocker() internal returns (address _locker) {
        // TODO change governance to the actual stake DAO governance
        _locker = address(new Locker(zeroLockerLp, address(this), address(zeroLpToken), address(veZeroLp)));
    }

    function _deployAccumulator() internal virtual returns (address payable _accumulator) {
        _accumulator = payable(address(new Accumulator(address(liquidityGauge), locker, address(this))));

        /// Set up the accumulator in the locker.
        vm.prank(ILocker(locker).governance());
        ILocker(locker).setAccumulator(address(accumulator));
    }

    function _deployLpDepositor() internal returns (address _lpDepositor) {
        _lpDepositor = address(new Depositor(address(zeroLpToken), locker, sdToken, address(liquidityGauge)));
    }

    function _createLpInitialLock() internal {
        // we need to initialize the ERC721 token locking
        zeroLpToken.transfer(locker, 1);
        ILocker(locker).createLock(1, 365 days);
    }

    function _setupLpContractGovernance() internal {
        ISdToken(sdToken).setOperator(address(depositor));
        ILocker(locker).setDepositor(address(depositor));
        ILocker(locker).setAccumulator(address(accumulator));

        _createLpInitialLock();

        liquidityGauge.add_reward(address(WETH), address(accumulator));
    }
}
