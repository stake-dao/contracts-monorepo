// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeProxyFactory} from "@safe/contracts/proxies/SafeProxyFactory.sol";
import {Safe, Enum} from "@safe/contracts/Safe.sol";
import {Common} from "address-book/src/CommonLinea.sol";
import {ZeroLocker} from "address-book/src/ZeroLinea.sol";
import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {IDepositor} from "src/interfaces/IDepositor.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {ISdToken} from "src/interfaces/ISdToken.sol";
import {ISafeLocker, ISafe} from "src/interfaces/ISafeLocker.sol";
import {sdToken as SdToken} from "src/SDToken.sol";
import {ZeroLendAccumulator} from "src/integrations/zerolend/Accumulator.sol";
import {Depositor} from "src/integrations/zerolend/Depositor.sol";
import {BaseZeroLendTest} from "test/fork/zerolend/common/BaseZeroLendTest.sol";

// end to end tests for the ZeroLend integration
abstract contract BaseZeroLendTokenTest is BaseZeroLendTest {
    address internal GOVERNANCE = address(1234);

    address internal zeroLockerToken = ZeroLocker.LOCKER_TOKEN;
    IERC20 internal zeroToken = IERC20(ZeroLocker.TOKEN);
    IERC20 internal veZero = IERC20(ZeroLocker.VE_ZERO);

    SafeProxyFactory internal safeProxyFactory = SafeProxyFactory(Common.SAFE_PROXY_FACTORY);
    address internal safeSingleton = Common.SAFE_SINGLETON;

    address internal zeroTokenHolder = 0xA05D8213472620292D4D96DCDA2Dd5dB4B65df2f;

    address[] internal feeSplitReceivers = new address[](2);
    uint256[] internal feeSplitFees = new uint256[](2);

    constructor() {}

    function _createLabels() internal {
        vm.label(address(zeroToken), "ZeroLend");
        vm.label(address(veZero), "veZero");
        vm.label(zeroLockerToken, "Locked ZERO Tokens (T-ZERO)");
        vm.label(0xb320Fa6C84d67145759f2e6B06e2Fc14B0BADb5d, "OmnichainStakingToken impl.");
        vm.label(Common.WETH, "WETH");
    }

    function _deployZeroIntegration() internal {
        _createLabels();

        sdToken = _deploySdZero();
        liquidityGauge = ILiquidityGauge(_deployLiquidityGauge(sdToken));
        locker = _deploySafeLocker();
        accumulator = AccumulatorBase(payable(_deployAccumulator()));
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

    function _getSafeInitializationData(address[] memory _owners, uint256 _threshold)
        internal
        pure
        returns (bytes memory initializer)
    {
        // bytes memory data = _getSetupData();
        initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            _owners,
            _threshold,
            address(0),
            abi.encodePacked(),
            address(0),
            address(0),
            0,
            address(0)
        );
    }

    function _deploySafeLocker() internal returns (address _locker) {
        uint256 _salt = uint256(keccak256(abi.encodePacked()));
        address[] memory _owners = new address[](1);
        _owners[0] = GOVERNANCE;
        uint256 _threshold = 1;

        bytes memory initializer = _getSafeInitializationData(_owners, _threshold);

        _locker = address(safeProxyFactory.createProxyWithNonce(safeSingleton, initializer, _salt));

        vm.prank(GOVERNANCE);
        ISafeLocker(_locker).execTransaction(
            address(zeroToken),
            0,
            abi.encodeWithSelector(IERC20.approve.selector, address(zeroLockerToken), type(uint256).max),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            abi.encodePacked(uint256(uint160(GOVERNANCE)), uint8(0), uint256(1))
        );
    }

    function _enableModule(address _module) internal {
        vm.prank(GOVERNANCE);
        ISafeLocker(locker).execTransaction(
            locker,
            0,
            abi.encodeWithSelector(ISafe.enableModule.selector, _module),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            abi.encodePacked(uint256(uint160(GOVERNANCE)), uint8(0), uint256(1))
        );
    }

    function _deployAccumulator() internal virtual returns (address payable _accumulator) {
        _accumulator = payable(address(new ZeroLendAccumulator(address(liquidityGauge), locker, GOVERNANCE)));

        // Add accumulator as a module on the Safe locker.
        _enableModule(_accumulator);
    }

    function _deployDepositor() internal returns (address _depositor) {
        _depositor = address(
            new Depositor(
                address(zeroToken), locker, sdToken, address(liquidityGauge), zeroLockerToken, address(veZero)
            )
        );

        // Add depositor as a module on the Safe locker.
        _enableModule(_depositor);
    }

    function _createInitialLock() internal {
        // we need to initialize the ERC721 token locking
        zeroToken.transfer(GOVERNANCE, 1);
        vm.prank(GOVERNANCE);
        zeroToken.approve(address(depositor), 1);
        vm.prank(GOVERNANCE);
        depositor.deposit(1, true, true, GOVERNANCE);
    }

    function _setupContractGovernance() internal {
        ISdToken(sdToken).setOperator(address(depositor));

        _createInitialLock();

        liquidityGauge.add_reward(address(zeroToken), address(accumulator));
        liquidityGauge.add_reward(address(WETH), address(accumulator));

        AccumulatorBase.Split[] memory splits = new AccumulatorBase.Split[](2);
        splits[0] = AccumulatorBase.Split(address(treasuryRecipient), 5e16);
        splits[1] = AccumulatorBase.Split(address(liquidityFeeRecipient), 10e16);

        vm.prank(GOVERNANCE);
        AccumulatorBase(accumulator).setFeeSplit(splits);
    }
}
