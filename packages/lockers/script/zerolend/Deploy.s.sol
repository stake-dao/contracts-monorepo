// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "script/common/DeployAccumulator.sol";

import {sdToken as SdToken} from "src/common/token/sdToken.sol";
import {Accumulator} from "src/linea/zerolend/Accumulator.sol";
import {Depositor} from "src/linea/zerolend/Depositor.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {IDepositor} from "src/common/interfaces/IDepositor.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {ILocker, ISafe} from "src/common/interfaces/zerolend/stakedao/ILocker.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeProxyFactory} from "@safe/contracts/proxies/SafeProxyFactory.sol";
import {Safe, Enum} from "@safe/contracts/Safe.sol";
import {SafeProxy} from "@safe/contracts/proxies/SafeProxy.sol";

// TODO create, import and use linea governance addresses
library DAO {
    address public constant MAIN_DEPLOYER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    address public constant TREASURY = address(2);
    address public constant LIQUIDITY_FEES_RECIPIENT = address(3);
    address public constant GOVERNANCE = address(4);
}

contract Deploy is DeployAccumulator {
    address sdZero;
    address liquidityGauge;
    address locker;
    address depositor;

    address zeroLockerToken = 0x08D5FEA625B1dBf9Bae0b97437303a0374ee02F8; // NFT token contract.
    address zeroToken = 0x78354f8DcCB269a615A7e0a24f9B0718FDC3C7A7;
    address veZero = 0xf374229a18ff691406f99CCBD93e8a3f16B68888;

    SafeProxyFactory safeProxyFactory = SafeProxyFactory(0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67);
    address safeSingleton = 0x41675C099F32341bf84BFc5382aF534df5C7461a;

    function run() public {
        vm.createSelectFork("linea");
        _run(DAO.MAIN_DEPLOYER, DAO.TREASURY, DAO.LIQUIDITY_FEES_RECIPIENT, DAO.GOVERNANCE);
    }

    function _getSafeInitializationData(address[] memory _owners, uint256 _threshold)
        internal
        pure
        returns (bytes memory initializer)
    {
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
        _owners[0] = DAO.MAIN_DEPLOYER;
        uint256 _threshold = 1;

        bytes memory initializer = _getSafeInitializationData(_owners, _threshold);

        _locker = address(safeProxyFactory.createProxyWithNonce(safeSingleton, initializer, _salt));

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
            abi.encodePacked(uint256(uint160(DAO.MAIN_DEPLOYER)), uint8(0), uint256(1))
        );
    }

    function _safeEnableModule(address _module) internal {
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
            abi.encodePacked(uint256(uint160(DAO.MAIN_DEPLOYER)), uint8(0), uint256(1))
        );
    }

    function _safeTransferSafeOwnershipToGovernance() internal {
        ILocker(locker).getOwners();

        ILocker(locker).execTransaction(
            locker,
            0,
            abi.encodeWithSelector(ISafe.addOwnerWithThreshold.selector, DAO.GOVERNANCE, 1),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            abi.encodePacked(uint256(uint160(DAO.MAIN_DEPLOYER)), uint8(0), uint256(1))
        );

        ILocker(locker).execTransaction(
            locker,
            0,
            abi.encodeWithSelector(ISafe.removeOwner.selector, DAO.GOVERNANCE, DAO.MAIN_DEPLOYER, 1),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            abi.encodePacked(uint256(uint160(DAO.MAIN_DEPLOYER)), uint8(0), uint256(1))
        );

        address[] memory _owners = ILocker(locker).getOwners();
    }

    function _safeApproveZeroLocker() internal {
        ILocker(locker).execTransaction(
            zeroToken,
            0,
            abi.encodeWithSelector(IERC20.approve.selector, zeroLockerToken, type(uint256).max),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            abi.encodePacked(uint256(uint160(DAO.MAIN_DEPLOYER)), uint8(0), uint256(1))
        );
    }

    function _beforeDeploy() internal virtual override {
        // Deploy locker.
        locker = _deploySafeLocker();

        // Deploy sdZero.
        // TODO confirm name & symbol
        sdZero = address((new SdToken("Stake DAO ZeroLend", "sdZERO")));

        // Deploy gauge.
        liquidityGauge = deployCode("vyper/LiquidityGaugeV4XChain.vy", abi.encode(sdZero, DAO.MAIN_DEPLOYER));

        // Deploy depositor.
        depositor =
            address(new Depositor(address(zeroToken), locker, sdZero, address(liquidityGauge), zeroLockerToken, veZero));
    }

    function _deployAccumulator() internal override returns (address payable) {
        require(sdZero != address(0));
        require(liquidityGauge != address(0));
        require(locker != address(0));

        return payable(new Accumulator(liquidityGauge, locker, DAO.MAIN_DEPLOYER));
    }

    function _afterDeploy() internal virtual override {
        // Setup access rights and rewards.
        ISdToken(sdZero).setOperator(address(depositor));

        _safeEnableModule(depositor);
        _safeEnableModule(accumulator);

        // approve zeroLocker for Zero
        _safeApproveZeroLocker();

        ILiquidityGauge(liquidityGauge).add_reward(address(zeroToken), address(accumulator));
        // Planned for future ZeroLend protocol upgrade.
        // liquidityGauge.add_reward(address(WETH), address(accumulator));

        // Transfer all governance to DAO for following contracts.
        //  - sdZero only has an operator which was set to the depositor
        //  - gauge (need to call accept_transfer_ownership() from DAO.GOVERNANCE)
        //  - depositor (need to call acceptGovernance() from DAO.GOVERNANCE)
        //  - accumulator is already taken care of in DeployAccumulator
        ILiquidityGauge(liquidityGauge).commit_transfer_ownership(DAO.GOVERNANCE);
        IDepositor(depositor).transferGovernance(DAO.GOVERNANCE);

        _safeTransferSafeOwnershipToGovernance();
    }
}
