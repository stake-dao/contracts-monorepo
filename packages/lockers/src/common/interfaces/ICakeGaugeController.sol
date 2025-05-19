// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface ICakeGaugeController {
    struct VotedSlope {
        uint256 slope;
        uint256 power;
        uint256 end;
    }

    function lastUserVote(address _user, bytes32 _gaugeHash) external view returns (uint256);

    function voteUserSlopes(address _user, bytes32 _gaugeHash) external view returns (VotedSlope memory);

    function voteUserPower(address _user) external returns (uint256);
}
