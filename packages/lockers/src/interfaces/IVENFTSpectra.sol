// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";

interface IVENFTSpectra is IERC721Enumerable {
    struct LockedBalance {
        uint256 amount;
        uint256 end;
        bool isPermanent;
    }

    function ownerToNFTokenIdList(address, uint256) external view returns (uint256);

    function locked(uint256 _tokenId) external view returns (LockedBalance memory);

    function depositFor(uint256 _tokenId, uint256 _value) external;

    function unlockPermanent(uint256 _tokenId) external;

    function lockPermanent(uint256 _tokenId) external;

    function merge(uint256 _from, uint256 _to) external;

    function createLock(uint256 _value, uint256 _lockDuration) external returns (uint256);

    function voter() external view returns (address);

    function voted(uint256 _tokenId) external view returns (bool);
}
