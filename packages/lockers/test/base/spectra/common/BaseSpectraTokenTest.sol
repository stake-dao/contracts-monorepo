// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/src/console.sol";
import {Enum} from "@safe/contracts/Safe.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {SafeLibrary} from "test/utils/SafeLibrary.sol";
import {Depositor} from "src/base/spectra/Depositor.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {Accumulator} from "src/base/spectra/Accumulator.sol";
import {sdToken as SdToken} from "src/common/token/sdToken.sol";
import {IDepositor} from "src/common/interfaces/IDepositor.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {BaseSpectraTest} from "test/base/spectra/common/BaseSpectraTest.sol";
import {ILocker, ISafe} from "src/common/interfaces/spectra/stakedao/ILocker.sol";
import {ISpectraRewardsDistributor} from "src/common/interfaces/spectra/spectra/ISpectraRewardsDistributor.sol";

// Base Spectra Test including deployments and setup
abstract contract BaseSpectraTokenTest is BaseSpectraTest {
    address GOVERNANCE = address(0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765);

    IERC20 spectraToken = IERC20(0x64FCC3A02eeEba05Ef701b7eed066c6ebD5d4E51);
    IERC721 veSpectra = IERC721(0x6a89228055C7C28430692E342F149f37462B478B);
    ISpectraRewardsDistributor spectraRewardsDistributor =
        ISpectraRewardsDistributor(0xBE6271FA207D2cD29C7F9efa90FC725C18560bff);

    constructor() {}

    function _createLabels() internal {
        vm.label(address(spectraToken), "SPECTRA");
        vm.label(address(veSpectra), "veSPECTRA");
    }

    function _deploySpectraIntegration() internal {
        _createLabels();

        sdToken = _deploySdSpectra();
        liquidityGauge = ILiquidityGauge(_deployLiquidityGauge(sdToken));
        locker = _deploySafeLocker();
        depositor = IDepositor(_deployDepositor());
        accumulator = BaseAccumulator(_deployAccumulator());

        _setupContractGovernance();
    }

    function _deploySdSpectra() internal returns (address _sdSpectra) {
        _sdSpectra = address((new SdToken("Stake DAO Spectra", "sdSPECTRA")));
    }

    function _deploySafeLocker() internal returns (address _locker) {
        uint256 salt = uint256(keccak256(abi.encodePacked()));
        address[] memory owners = new address[](1);
        owners[0] = GOVERNANCE;

        _locker = address(SafeLibrary.deploySafe({_owners: owners, _threshold: 1, _saltNonce: salt}));

        vm.prank(GOVERNANCE);
        ILocker(_locker).execTransaction(
            address(spectraToken),
            0,
            abi.encodeWithSelector(IERC20.approve.selector, address(veSpectra), type(uint256).max),
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

    function _deployDepositor() internal returns (address _depositor) {
        _depositor = address(new Depositor(address(spectraToken), locker, sdToken, address(liquidityGauge)));

        // Add depositor as a module on the Safe locker.
        _enableModule(_depositor);
    }

    function _deployAccumulator() internal virtual returns (address payable _accumulator) {
        _accumulator =
            payable(address(new Accumulator(address(liquidityGauge), sdToken, locker, GOVERNANCE, address(depositor))));
    }

    function _setupContractGovernance() internal {
        ISdToken(sdToken).setOperator(address(depositor));

        liquidityGauge.add_reward(sdToken, address(accumulator));

        vm.prank(GOVERNANCE);
        accumulator.setClaimerFee(0);
    }
}
