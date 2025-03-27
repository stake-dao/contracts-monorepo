// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "script/common/DeployAccumulator.sol";
import {Safe, Enum} from "@safe/contracts/Safe.sol";
import {DAO} from "address-book/src/dao/8453.sol";
import {Spectra} from "address-book/src/protocols/8453.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeProxyFactory} from "@safe/contracts/proxies/SafeProxyFactory.sol";

import {Depositor} from "src/base/spectra/Depositor.sol";
import {Accumulator} from "src/base/spectra/Accumulator.sol";
import {sdToken as SdToken} from "src/common/token/sdToken.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {ILocker, ISafe} from "src/common/interfaces/spectra/stakedao/ILocker.sol";

contract Deploy is DeployAccumulator {
    address sdSpectra;
    address liquidityGauge;
    address locker;
    address depositor;

    SafeProxyFactory safeProxyFactory = SafeProxyFactory(0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67);
    address safeSingleton = 0x41675C099F32341bf84BFc5382aF534df5C7461a;

    function run() public {
        vm.createSelectFork("base");
        _run(DAO.MAIN_DEPLOYER, DAO.TREASURY, DAO.TREASURY, DAO.GOVERNANCE);
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
        owners[0] = DAO.MAIN_DEPLOYER;

        uint256 threshold = 1;
        bytes memory initializer = _getSafeInitializationData(owners, threshold);
        _locker = address(safeProxyFactory.createProxyWithNonce(safeSingleton, initializer, salt));

        ILocker(_locker).execTransaction(
            Spectra.SPECTRA,
            0,
            abi.encodeWithSelector(IERC20.approve.selector, Spectra.VESPECTRA, type(uint256).max),
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
    }

    function _beforeDeploy() internal virtual override {
        // Deploy locker.
        locker = _deploySafeLocker();

        // Deploy sdSpectra.
        sdSpectra = address((new SdToken("Stake DAO SPECTRA", "sdSPECTRA")));

        // Deploy gauge.
        liquidityGauge = deployCode("vyper/LiquidityGaugeV4XChain.vy", abi.encode(sdSpectra, DAO.MAIN_DEPLOYER));

        // Deploy depositor.
        depositor = address(new Depositor(Spectra.SPECTRA, locker, sdSpectra, liquidityGauge));
    }

    function _deployAccumulator() internal override returns (address payable) {
        require(sdSpectra != address(0));
        require(liquidityGauge != address(0));
        require(locker != address(0));
        require(depositor != address(0));

        return payable(new Accumulator(liquidityGauge, sdSpectra, locker, DAO.MAIN_DEPLOYER, depositor));
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
