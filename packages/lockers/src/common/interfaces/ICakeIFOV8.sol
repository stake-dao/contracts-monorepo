// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface ICakeIFOV8 {
    struct VestingSchedule {
        bool isVestingInitialized;
        address beneficiary;
        uint8 pid;
        uint256 amountTotal;
        uint256 released;
    }

    function addresses(uint256) external view returns (address);

    function computeVestingScheduleIdForAddressAndPid(address holder, uint8 pid) external view returns (bytes32);

    function depositPool(uint256 amount, uint8 pid) external;

    function getVestingSchedule(bytes32 vestingSchedule) external view returns (VestingSchedule memory);

    function harvestPool(uint8 pid) external;

    function startTimestamp() external view returns (uint256);

    function endTimestamp() external view returns (uint256);

    function viewPoolInformation(uint256 pid)
        external
        returns (uint256, uint256, uint256, bool, uint256, uint256, uint8);

    function viewPoolVestingInformation(uint256 pid) external returns (uint256, uint256, uint256, uint256);

    function vestingStartTime() external returns (uint256);

    function totalTokensOffered() external view returns (uint256);
}
