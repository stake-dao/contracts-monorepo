// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IDepositorBase {
    function createLock(uint256 _amount) external;
    function depositAll(bool _lock, bool _stake, address _user) external;
    function deposit(uint256 _amount, bool _lock, bool _stake, address _user) external;
    function lockToken() external;
    function transferGovernance(address _governance) external;
    function acceptGovernance() external;
    function shutdown(address receiver) external;
    function shutdown() external;
    function setSdTokenMinterOperator(address _minter) external;
    function setGauge(address _gauge) external;
    function setFees(uint256 _lockIncentive) external;
    function name() external view returns (string memory);
    function version() external pure returns (string memory);
    function incentiveToken() external view returns (uint256);
    function gauge() external view returns (address);
    function governance() external view returns (address);
    function futureGovernance() external view returns (address);
    function locker() external view returns (address);
    function token() external view returns (address);
    function minter() external view returns (address);
    function lockIncentivePercent() external view returns (uint256);
    function MAX_LOCK_DURATION() external view returns (uint256);
    function DENOMINATOR() external view returns (uint256);
}
