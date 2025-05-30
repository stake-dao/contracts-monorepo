// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.28;

// ███████╗███████╗██████╗  ██████╗
// ╚══███╔╝██╔════╝██╔══██╗██╔═══██╗
//   ███╔╝ █████╗  ██████╔╝██║   ██║
//  ███╔╝  ██╔══╝  ██╔══██╗██║   ██║
// ███████╗███████╗██║  ██║╚██████╔╝
// ╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝

// Website: https://zerolend.xyz
// Discord: https://discord.gg/zerolend
// Twitter: https://twitter.com/zerolendxyz

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

interface IZeroVp is IVotes {
    // An omni-chain staking contract that allows users to stake their veNFT
    // and get some voting power. Once staked the voting power is available cross-chain.

    /**
     * @notice Structure to store locked balance information
     * @param amount Amount of tokens locked
     * @param end End time of the lock period (timestamp)
     * @param start Start time of the lock period (timestamp)
     * @param power Additional parameter, potentially for governance or staking power
     */
    struct LockedBalance {
        uint256 amount;
        uint256 end;
        uint256 start;
        uint256 power;
    }

    error ERC721NonexistentToken(uint256);

    function rewards(address) external view returns (uint256);

    function increaseLockAmount(uint256 tokenId, uint256 newLockAmount) external;

    function increaseLockDuration(uint256 tokenId, uint256 newLockDuration) external;

    function rewardRate() external returns (uint256);

    function getReward() external;

    function unstakeToken(uint256 tokenId) external;

    function getLockedNftDetails(address _user) external view returns (uint256[] memory, LockedBalance[] memory);

    function lockedTokenIdNfts(address _user, uint256 _index) external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);
}
