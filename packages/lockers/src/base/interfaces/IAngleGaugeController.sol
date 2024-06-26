// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

interface IAngleGaugeController {
    function vote_for_gauge_weights(address, uint256) external;

    function vote(uint256, bool, bool) external; //voteId, support, executeIfDecided

    function gauges(uint256 _id) external view returns (address _address);

    function last_user_vote(address _user, address _gauge) external view returns (uint256 _timestamp);
}
