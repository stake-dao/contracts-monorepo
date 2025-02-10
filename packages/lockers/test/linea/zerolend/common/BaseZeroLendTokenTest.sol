// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/console.sol";

import {BaseZeroLendTest} from "test/linea/zerolend/common/BaseZeroLendTest.sol";

import "src/linea/zerolend/Accumulator.sol";
import {sdToken as SdToken} from "src/common/token/sdToken.sol";
import {Depositor} from "src/linea/zerolend/Depositor.sol";

import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {ILocker, ISafe} from "src/common/interfaces/zerolend/stakedao/ILocker.sol";
import {IDepositor} from "src/common/interfaces/IDepositor.sol";
import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeProxyFactory} from "@safe/contracts/proxies/SafeProxyFactory.sol";
import {Safe, Enum} from "@safe/contracts/Safe.sol";
import {SafeProxy} from "@safe/contracts/proxies/SafeProxy.sol";

// end to end tests for the ZeroLend integration
abstract contract BaseZeroLendTokenTest is BaseZeroLendTest {
    address GOVERNANCE = address(1234);

    address zeroLockerToken = 0x08D5FEA625B1dBf9Bae0b97437303a0374ee02F8;
    IERC20 zeroToken = IERC20(0x78354f8DcCB269a615A7e0a24f9B0718FDC3C7A7);
    IERC20 veZero = IERC20(0xf374229a18ff691406f99CCBD93e8a3f16B68888);

    SafeProxyFactory safeProxyFactory = SafeProxyFactory(0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67);
    address safeSingleton = 0x41675C099F32341bf84BFc5382aF534df5C7461a;

    address zeroTokenHolder = 0xA05D8213472620292D4D96DCDA2Dd5dB4B65df2f;

    address[] feeSplitReceivers = new address[](2);
    uint256[] feeSplitFees = new uint256[](2);

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
        locker = _deploySafeLocker();
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
        ILocker(_locker).execTransaction(
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
        ILocker(locker).execTransaction(
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
        _accumulator = payable(address(new Accumulator(address(liquidityGauge), locker, GOVERNANCE)));

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

        // setup fee split
        feeSplitReceivers[0] = address(treasuryRecipient);
        feeSplitFees[0] = 5e16; // 5% to dao

        feeSplitReceivers[1] = address(liquidityFeeRecipient);
        feeSplitFees[1] = 10e16; // 10% to liquidity

        vm.prank(GOVERNANCE);
        BaseAccumulator(accumulator).setFeeSplit(feeSplitReceivers, feeSplitFees);
    }
}
