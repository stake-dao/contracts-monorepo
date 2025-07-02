// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeProxyFactory} from "@safe/contracts/proxies/SafeProxyFactory.sol";
import {Safe, Enum} from "@safe/contracts/Safe.sol";
import {Common} from "@address-book/src/CommonLinea.sol";
import {DAO} from "@address-book/src/DaoLinea.sol";
import {ZeroLocker} from "@address-book/src/ZeroLinea.sol";
import {DeployAccumulator} from "script/common/DeployAccumulator.sol";
import {IDepositor} from "src/interfaces/IDepositor.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {ISdToken} from "src/interfaces/ISdToken.sol";
import {ISafeLocker, ISafe} from "src/interfaces/ISafeLocker.sol";
import {sdToken as SdToken} from "src/SDToken.sol";
import {ZeroLendAccumulator} from "src/integrations/zerolend/Accumulator.sol";
import {Depositor} from "src/integrations/zerolend/Depositor.sol";

contract Deploy is DeployAccumulator {
    address internal sdZero;
    address internal liquidityGauge;
    address internal locker;
    address internal depositor;

    address internal zeroLockerToken = ZeroLocker.LOCKER_TOKEN; // NFT token contract.
    address internal zeroToken = ZeroLocker.TOKEN;
    address internal veZero = ZeroLocker.VE_ZERO;

    SafeProxyFactory internal safeProxyFactory = SafeProxyFactory(Common.SAFE_PROXY_FACTORY);
    address internal safeSingleton = Common.SAFE_SINGLETON;

    function run() public {
        vm.createSelectFork("linea");
        _run(DAO.TREASURY, DAO.TREASURY, DAO.GOVERNANCE);
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
        _owners[0] = msg.sender;
        uint256 _threshold = 1;

        bytes memory initializer = _getSafeInitializationData(_owners, _threshold);

        _locker = address(safeProxyFactory.createProxyWithNonce(safeSingleton, initializer, _salt));

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
            abi.encodePacked(uint256(uint160(msg.sender)), uint8(0), uint256(1))
        );
    }

    function _safeEnableModule(address _module) internal {
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
            abi.encodePacked(uint256(uint160(msg.sender)), uint8(0), uint256(1))
        );
    }

    function _safeTransferSafeOwnershipToGovernance() internal {
        ISafeLocker(locker).getOwners();

        ISafeLocker(locker).execTransaction(
            locker,
            0,
            abi.encodeWithSelector(ISafe.addOwnerWithThreshold.selector, DAO.GOVERNANCE, 1),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            abi.encodePacked(uint256(uint160(msg.sender)), uint8(0), uint256(1))
        );

        ISafeLocker(locker).execTransaction(
            locker,
            0,
            abi.encodeWithSelector(ISafe.removeOwner.selector, DAO.GOVERNANCE, msg.sender, 1),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            abi.encodePacked(uint256(uint160(msg.sender)), uint8(0), uint256(1))
        );
    }

    function _safeApproveZeroLocker() internal {
        ISafeLocker(locker).execTransaction(
            zeroToken,
            0,
            abi.encodeWithSelector(IERC20.approve.selector, zeroLockerToken, type(uint256).max),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            abi.encodePacked(uint256(uint160(msg.sender)), uint8(0), uint256(1))
        );
    }

    function _beforeDeploy() internal virtual override {
        // Deploy locker.
        locker = _deploySafeLocker();

        // Deploy sdZero.
        // TODO confirm name & symbol
        sdZero = address((new SdToken("Stake DAO ZeroLend", "sdZERO")));

        // Deploy gauge.
        liquidityGauge = deployCode("GaugeLiquidityV4XChain.vy", abi.encode(sdZero, msg.sender));

        // Deploy depositor.
        depositor =
            address(new Depositor(address(zeroToken), locker, sdZero, address(liquidityGauge), zeroLockerToken, veZero));
    }

    function _deployAccumulator() internal override returns (address payable) {
        require(sdZero != address(0));
        require(liquidityGauge != address(0));
        require(locker != address(0));

        return payable(new ZeroLendAccumulator(liquidityGauge, locker, msg.sender));
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

    function deployBytecode(bytes memory _bytecode, bytes memory _constructorData)
        internal
        returns (address _deployed)
    {
        bytes memory bytecode = abi.encodePacked(_bytecode, _constructorData);
        assembly {
            _deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(_deployed != address(0), "Failed to deploy contract");
    }
}
