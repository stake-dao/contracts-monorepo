// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IVotingEscrow {
    struct Checkpoint {
        uint32 fromBlock;
        uint224 votes;
    }

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
    event EIP712DomainChanged();
    event Stake(address indexed user, uint256 lockupId, uint256 amount, uint256 end, uint256 points);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Unstake(address indexed user, uint256 lockupId, uint256 amount, uint256 end, uint256 points);

    function approve(address spender, uint256 amount) external returns (bool);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function delegate(address delegatee) external;
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external;
    function extend(uint256 lockupId, uint256 duration, uint256 amount, bool doDelegation) external;
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function stake(uint256 amount, uint256 duration, bool doDelegation) external;
    function stake(uint256 amount, uint256 duration, address to) external;
    function unstake(uint256 lockupId) external;
    function transfer(address, uint256) external pure returns (bool);
    function transferFrom(address, address, uint256) external pure returns (bool);
    function CLOCK_MODE() external view returns (string memory);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function YEAR_BASE() external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function checkpoints(address account, uint32 pos) external view returns (Checkpoint memory);
    function clock() external view returns (uint48);
    function decimals() external view returns (uint8);
    function delegates(address account) external view returns (address);
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );
    function epoch() external view returns (uint256);
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
    function getVotes(address account) external view returns (uint256);
    function lockupCount(address staker) external view returns (uint256 count);
    function lockups(address, uint256) external view returns (uint128 amount, uint128 end, uint256 points);
    function mav() external view returns (address);
    function maxStakeDuration() external view returns (uint256);
    function minStakeDuration() external view returns (uint256);
    function name() external view returns (string memory);
    function nonces(address owner) external view returns (uint256);
    function numCheckpoints(address account) external view returns (uint32);
    function previewPoints(uint256 amount, uint256 duration) external view returns (uint256, uint256);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
}
