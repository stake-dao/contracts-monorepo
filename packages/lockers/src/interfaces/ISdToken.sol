// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface ISdToken {
    function balanceOf(address account) external view returns (uint256);

    function burn(uint256 amount) external;

    function burn(address _to, uint256 _amount) external;

    function mint(address _to, uint256 _amount) external;

    function operator() external view returns (address);

    function burner() external view returns (address);

    function setOperator(address _operator) external;

    function setBurnerOperator(address _burner) external;

    function approve(address _spender, uint256 _amount) external;
}
