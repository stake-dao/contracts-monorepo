// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeProxyFactory} from "@safe/contracts/proxies/SafeProxyFactory.sol";
import {Safe, Enum} from "@safe/contracts/Safe.sol";
import {DAO} from "address-book/src/DAOBase.sol";
import {SpectraProtocol} from "address-book/src/SpectraBase.sol";
import {DeployAccumulator} from "script/common/DeployAccumulator.sol";
import {Accumulator} from "src/base/spectra/Accumulator.sol";
import {Depositor} from "src/base/spectra/Depositor.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {ILocker, ISafe} from "src/common/interfaces/spectra/stakedao/ILocker.sol";
import {sdToken as SdToken} from "src/common/token/sdToken.sol";
import {Common} from "address-book/src/CommonBase.sol";

contract Deploy is DeployAccumulator {
    address internal sdSpectra;
    address internal liquidityGauge;
    address internal locker;
    address internal depositor;

    SafeProxyFactory internal safeProxyFactory = SafeProxyFactory(Common.SAFE_PROXY_FACTORY);
    address internal safeSingleton = Common.SAFE_SINGLETON;

    function run() public {
        vm.createSelectFork("base");
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
        uint256 salt = uint256(keccak256(abi.encodePacked()));
        address[] memory owners = new address[](1);
        owners[0] = msg.sender;

        uint256 threshold = 1;
        bytes memory initializer = _getSafeInitializationData(owners, threshold);
        _locker = address(safeProxyFactory.createProxyWithNonce(safeSingleton, initializer, salt));

        ILocker(_locker).execTransaction(
            SpectraProtocol.SPECTRA,
            0,
            abi.encodeWithSelector(IERC20.approve.selector, SpectraProtocol.VESPECTRA, type(uint256).max),
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
            abi.encodePacked(uint256(uint160(msg.sender)), uint8(0), uint256(1))
        );
    }

    function _safeTransferSafeOwnershipToGovernance() internal {
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
            abi.encodePacked(uint256(uint160(msg.sender)), uint8(0), uint256(1))
        );

        ILocker(locker).execTransaction(
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

    function _beforeDeploy() internal virtual override {
        // Deploy locker.
        locker = _deploySafeLocker();

        // Deploy sdSpectra.
        sdSpectra = address((new SdToken("Stake DAO SPECTRA", "sdSPECTRA")));

        // Deploy gauge.
        liquidityGauge = deployCode("vyper/LiquidityGaugeV4XChain.vy", abi.encode(sdSpectra, msg.sender));

        // Deploy depositor.
        depositor = address(new Depositor(SpectraProtocol.SPECTRA, locker, sdSpectra, liquidityGauge));
    }

    function _deployAccumulator() internal override returns (address payable) {
        require(sdSpectra != address(0));
        require(liquidityGauge != address(0));
        require(locker != address(0));
        require(depositor != address(0));

        return payable(new Accumulator(liquidityGauge, sdSpectra, locker, msg.sender, depositor));
    }

    function _afterDeploy() internal virtual override {
        // Add sdSpectra minting rights to depositor
        SdToken(sdSpectra).setOperator(address(depositor));

        // Enable depositor as a module
        // NB: Accumulator doesn't require module rights
        _safeEnableModule(depositor);

        // Add acumulator as distributor of sdSPECTRA
        ILiquidityGauge(liquidityGauge).add_reward(address(sdSpectra), address(accumulator));

        // Set claimer fee as 0 as it's sidechain
        Accumulator(accumulator).setClaimerFee(0);

        // Transfer all governance to DAO for following contracts.
        //  - gauge (need to call accept_transfer_ownership() from DAO.GOVERNANCE)
        //  - depositor (need to call acceptGovernance() from DAO.GOVERNANCE)
        //  - accumulator is already taken care of in DeployAccumulator
        ILiquidityGauge(liquidityGauge).commit_transfer_ownership(DAO.GOVERNANCE);
        Depositor(depositor).transferGovernance(DAO.GOVERNANCE);

        _safeTransferSafeOwnershipToGovernance();
    }
}
