// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {Accountant} from "src/Accountant.sol";

// Exposes the useful internal functions of the Accountant contract for testing purposes
contract AccountantHarness is Accountant, Test {
    constructor(address _owner, address _registry, address _rewardToken, bytes4 _protocolId)
        Accountant(_owner, _registry, _rewardToken, _protocolId)
    {}

    function exposed_defaultProtocolFee() external pure returns (uint128) {
        return DEFAULT_PROTOCOL_FEE;
    }

    function exposed_defaultHarvestFee() external pure returns (uint128) {
        return DEFAULT_HARVEST_FEE;
    }

    function exposed_feeSubjectAmount(address vault) external view returns (uint128) {
        return vaults[vault].feeSubjectAmount;
    }

    function exposed_integral(address vault) external view returns (uint256) {
        return vaults[vault].integral;
    }

    function exposed_integralUser(address vault, address account) external view returns (uint256) {
        return accounts[vault][account].integral;
    }

    function _cheat_updateVaultData(address vault, VaultData memory data) external {
        vaults[vault] = data;
    }

    function _cheat_updateUserData(address vault, address account, AccountData memory data) external {
        accounts[vault][account] = data;
    }

    function _cheat_updateFeesParamsProtocolFeePercent(uint128 value) external {
        feesParams.protocolFeePercent = value;
    }

    function _cheat_updateFeesParamsHarvestFeePercent(uint128 value) external {
        feesParams.harvestFeePercent = value;
    }
}
