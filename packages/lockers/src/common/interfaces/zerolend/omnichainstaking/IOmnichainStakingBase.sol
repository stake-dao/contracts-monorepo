// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

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
import {ILocker} from "./ILocker.sol";

interface IOmnichainStakingBase is IVotes {
    // An omni-chain staking contract that allows users to stake their veNFT
    // and get some voting power. Once staked the voting power is available cross-chain.

    error ERC721NonexistentToken(uint256);

    function rewards(address) external view returns (uint256);

    function increaseLockAmount(uint256 tokenId, uint256 newLockAmount) external;

    function increaseLockDuration(uint256 tokenId, uint256 newLockDuration) external;

    function getReward() external;

    function unstakeToken(uint256 tokenId) external;

    function getLockedNftDetails(address _user)
        external
        view
        returns (uint256[] memory, ILocker.LockedBalance[] memory);

    function lockedTokenIdNfts(address _user, uint256 _index) external view returns (uint256);
}
