// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Enum} from "@safe/contracts/Safe.sol";
import {DAO} from "address-book/src/DaoBase.sol";
import {SpectraLocker} from "address-book/src/SpectraBase.sol";
import {ISpectraVoter} from "src/interfaces/ISpectraVoter.sol";
import {ISafeLocker, ISafe} from "src/interfaces/ISafeLocker.sol";
import {SpectraVoter} from "src/integrations/spectra/SpectraVoter.sol";
import {VoterPermissionManager} from "src/VoterPermissionManager.sol";
import {BaseTest} from "test/BaseTest.t.sol";

contract SpectraGaugeVoterTest is BaseTest {
    SpectraVoter internal spectraVoter;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("base"), 30_481_499);

        // Deploy the voter
        spectraVoter = new SpectraVoter(address(SpectraLocker.LOCKER));

        // Enable the voter as a Safe module of the locker Safe Account, as this is the new version of the locker.
        _enableModule(spectraVoter.LOCKER(), address(spectraVoter));
        assertEq(ISafeLocker(spectraVoter.LOCKER()).isModuleEnabled(address(spectraVoter)), true);

        // Allow this contract to call `SpectraVoter.voteGauges`
        vm.prank(spectraVoter.governance());
        spectraVoter.setPermission(address(this), VoterPermissionManager.Permission.GAUGES_ONLY);

        // Label the important addresses
        vm.label(address(spectraVoter), "SpectraVoter");
        vm.label(spectraVoter.LOCKER(), "SpectraLocker");
    }

    function testVoteGauges() public {
        // Compute vote params
        uint256 nbGauges = 1;
        uint160[] memory pools = new uint160[](nbGauges);
        pools[0] = uint160(1285096718668641499024068352622928265951946908010);

        uint256[] memory weights = new uint256[](nbGauges);
        weights[0] = 1000000000000000000;

        // Execute vote
        spectraVoter.voteGauges(pools, weights);

        // Check the vote used the correct amount of weights
        uint256 usedWeights =
            ISpectraVoter(spectraVoter.VOTER()).usedWeights(spectraVoter.VE_SPECTRA(), spectraVoter.TOKEN_ID());
        uint256 totalWeightUsed;
        for (uint256 i; i < nbGauges; i++) {
            totalWeightUsed +=
                ISpectraVoter(spectraVoter.VOTER()).votes(spectraVoter.VE_SPECTRA(), spectraVoter.TOKEN_ID(), pools[i]);
        }

        assertTrue(totalWeightUsed == usedWeights);
    }

    ////////////////////////////////////////////////////////////////
    /// --- UTILS FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Enable a module in the Gateway.
    function _enableModule(address _locker, address _module) internal {
        vm.prank(DAO.GOVERNANCE);
        ISafeLocker(_locker).execTransaction(
            _locker,
            0,
            abi.encodeWithSelector(ISafe.enableModule.selector, _module),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            abi.encodePacked(uint256(uint160(DAO.GOVERNANCE)), uint8(0), uint256(1))
        );
    }
}
