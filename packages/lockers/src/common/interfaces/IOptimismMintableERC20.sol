// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IERC165} from "openzeppelin-contracts/interfaces/IERC165.sol";

interface IOptimismMintableERC20 is IERC165 {
    function remoteToken() external view returns (address);

    function bridge() external returns (address);

    function mint(address _to, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;
}
