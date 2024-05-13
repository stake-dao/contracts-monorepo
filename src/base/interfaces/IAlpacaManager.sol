// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAlpacaManager {
    struct TokenAmount {
        address token;
        uint256 amount;
    }

    function getWorker(address _vaultToken) external view returns (address _worker);

    function deposit(
        address _depositFor,
        address _vaultToken,
        TokenAmount[] calldata _depositParams,
        uint256 _minReceive
    ) external returns (bytes memory _result);

    function withdraw(address _vaultToken, uint256 _sharesToWithdraw, TokenAmount[] calldata _minAmountOuts)
        external
        returns (TokenAmount[] memory _results);

    function totalSupply() external view returns (uint256);

    function vaultManager() external view returns (address);
}
