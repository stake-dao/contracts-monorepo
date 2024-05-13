// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IAdapter {
    function initialize(address _vault, address _stakingToken) external;

    function vault() external returns (address);

    function PROTOCOL() external returns (string memory);

    function stakingToken() external returns (address);

    function token0() external returns (address);

    function token1() external returns (address);

    function deposit(uint256 _amount0, uint256 _amount1, address _user, bytes calldata _data)
        external
        returns (uint256 _share);

    function withdraw(uint256 _share, address _user, bytes calldata _data)
        external
        returns (uint256 _amount0, uint256 _amount1);
}
