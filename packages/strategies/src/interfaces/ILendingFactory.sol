// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IStrategyWrapper} from "src/interfaces/IStrategyWrapper.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IOracle} from "src/interfaces/IOracle.sol";
import {Id} from "shared/src/morpho/IMorpho.sol";

interface ILendingFactory {
    function protocol() external view returns (address);

    function create(
        IStrategyWrapper collateral,
        IERC20Metadata loan,
        IOracle oracle,
        address irm,
        uint256 lltv,
        uint256 initialLoanSupply
    ) external returns (Id);
}
