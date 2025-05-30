// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IYearnVestingFactory {
    function OWNER() external returns (address);
    function YFI() external view returns (address);

    function create_vest(address recipient, uint256 amount, uint256 vesting_duration) external returns (uint256);
    function deploy_vesting_contract(uint256 idx, address token, uint256 amount) external returns (address, uint256);
    function set_liquid_locker(address liquid_locker, address depositor) external;
}
