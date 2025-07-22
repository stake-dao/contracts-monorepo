// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IPendleGauge} from "src/interfaces/IPendleGauge.sol";

interface IPendleMarket is IERC20Metadata, IPendleGauge {
    struct MarketState {
        int256 totalPt;
        int256 totalSy;
        int256 totalLp;
        address treasury;
        /// immutable variables ///
        int256 scalarRoot;
        uint256 expiry;
        /// fee data ///
        uint256 lnFeeRateRoot;
        uint256 reserveFeePercent; // base 100
        /// last trade data ///
        uint256 lastLnImpliedRate;
    }

    function mint(address receiver, uint256 netSyDesired, uint256 netPtDesired)
        external
        returns (uint256 netLpOut, uint256 netSyUsed, uint256 netPtUsed);

    function burn(address receiverSy, address receiverPt, uint256 netLpToBurn)
        external
        returns (uint256 netSyOut, uint256 netPtOut);

    function swapExactPtForSy(address receiver, uint256 exactPtIn, bytes calldata data)
        external
        returns (uint256 netSyOut, uint256 netSyFee);

    function swapSyForExactPt(address receiver, uint256 exactPtOut, bytes calldata data)
        external
        returns (uint256 netSyIn, uint256 netSyFee);

    function redeemRewards(address user) external returns (uint256[] memory);

    function readState(address router) external view returns (MarketState memory market);

    function observe(uint32[] memory secondsAgos) external view returns (uint216[] memory lnImpliedRateCumulative);

    function increaseObservationsCardinalityNext(uint16 cardinalityNext) external;

    function getRewardTokens() external view returns (address[] memory);

    function isExpired() external view returns (bool);

    function expiry() external view returns (uint256);

    function observations(uint256 index)
        external
        view
        returns (uint32 blockTimestamp, uint216 lnImpliedRateCumulative, bool initialized);

    function _storage()
        external
        view
        returns (
            int128 totalPt,
            int128 totalSy,
            uint96 lastLnImpliedRate,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext
        );
}
