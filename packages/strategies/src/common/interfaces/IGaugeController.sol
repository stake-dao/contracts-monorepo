// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IGaugeController {
    // solhint-disable-next-line
    function add_gauge(address, int128, uint256) external;

    // solhint-disable-next-line
    function add_type(string memory, uint256) external;

    // solhint-disable-next-line
    function get_gauge_weight(address _gauge) external view returns (uint256);

    // solhint-disable-next-line
    function last_user_vote(address _user, address _gauge) external view returns (uint256);

    // solhint-disable-next-line
    function vote_for_gauge_weights(address _gauge, uint256 _weight) external;

    //solhint-disable-next-line
    function gauge_relative_weight(address addr) external view returns (uint256);
}
