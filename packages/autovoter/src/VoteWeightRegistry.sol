// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

contract VoteWeightRegistry {

    struct Vote {
        address user;
        address[] gauges;
        uint256[] chainIds;
        uint256[] weights;
        string[] metadatas;
        bool killed;
    }

    mapping(string => mapping(uint256 => Vote)) public votes;

    // Index start to one
    mapping(string => uint256) public space_votes_index;
    mapping(address => mapping(string => uint256)) public user_vote_index;
    
    function set(string calldata space, address[] calldata _gauges, uint256[] calldata _chainIds, uint256[] calldata _weights, string[] calldata _metadatas) external {
        uint256 weightLength = _weights.length;

        require(_gauges.length == weightLength, "!Gauges length");
        require(_gauges.length == _chainIds.length, "!Chain ids length");
        require(_gauges.length == _metadatas.length, "!Metadata length");

        uint256 sum = 0;
        uint256 i = 0;
        
        for(;i<weightLength;) {
            sum += _weights[i];
            
            unchecked {
                ++i;
            }
        }

        require(sum == 10000, "Wrong weight");

        uint256 userVoteIndex = user_vote_index[msg.sender][space];
        if(userVoteIndex == 0) {
            // New vote
            userVoteIndex = get_new_index(space);
        }

        votes[space][userVoteIndex] = Vote({
            user: msg.sender,
            gauges: _gauges,
            weights: _weights,
            chainIds: _chainIds,
            metadatas: _metadatas,
            killed: false
        });
    }

    function get_new_index(string calldata space) internal returns(uint256) {
        // New vote
        uint256 currentIndex = space_votes_index[space];
        uint256 userVoteIndex = currentIndex + 1;

        space_votes_index[space] = userVoteIndex;
        user_vote_index[msg.sender][space] = userVoteIndex;

        return userVoteIndex;
    }

    function remove(string calldata space) public {
        uint256 index = user_vote_index[msg.sender][space];
        require(index > 0, "No vote");
        

        votes[space][index].killed = true;
    }

    function removeAll(string[] calldata spaces) public {
        for(uint256 i = 0; i < spaces.length; ++i) {
            remove(spaces[i]);
        }
    }

    function get(address user, string calldata space) external view returns(Vote memory) {
        uint256 index = user_vote_index[user][space];
        return votes[space][index];
    }
}