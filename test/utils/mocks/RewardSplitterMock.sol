// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {IRewardSplitter} from "herdaddy/interfaces/IRewardSplitter.sol";

contract MockRewardSplitter is IRewardSplitter {
    address public override governance;
    address public override futureGovernance;
    address public override dao;
    address public override veSdtFeeProxy;

    // Adjust the state variable declarations to private to prevent automatic getter functions
    mapping(address => address) private _rewardTokenAccumulator;
    mapping(address => IRewardSplitter.RewardRepartition) private _rewardTokenRepartition;

    function rewardTokenAccumulator(address rewardToken) external view override returns (address) {
        return _rewardTokenAccumulator[rewardToken];
    }

    function rewardTokenRepartition(address rewardToken)
        external
        view
        override
        returns (IRewardSplitter.RewardRepartition memory)
    {
        return _rewardTokenRepartition[rewardToken];
    }

    function setGovernance(address _governance) public {
        governance = _governance;
    }

    function setFutureGovernance(address _futureGovernance) public {
        futureGovernance = _futureGovernance;
    }

    function setDao(address _dao) public override {
        dao = _dao;
    }

    function setVeSdtFeeProxy(address _veSdtFeeProxy) public override {
        veSdtFeeProxy = _veSdtFeeProxy;
    }

    function split(address rewardToken) public override {
        // For test purposes, split will send everything to the accumulator
        
        ERC20(rewardToken).transfer(_rewardTokenAccumulator[rewardToken], ERC20(rewardToken).balanceOf(address(this)));
    }

    function transferGovernance(address _futureGovernance) public override {
        futureGovernance = _futureGovernance;
    }

    function acceptGovernance() public override {
        governance = futureGovernance;
    }

    function setRewardTokenAccumulator(address rewardToken, address accumulator) public {
        _rewardTokenAccumulator[rewardToken] = accumulator;
    }

    function setRewardTokenAndRepartition(
        address rewardToken,
        address accumulator,
        uint256 daoPart,
        uint256 accumulatorPart,
        uint256 veSdtFeeProxyPart
    ) public override {
        _rewardTokenAccumulator[rewardToken] = accumulator;
        _rewardTokenRepartition[rewardToken] = RewardRepartition(daoPart, accumulatorPart, veSdtFeeProxyPart);
    }

    function setRepartition(address rewardToken, uint256 daoPart, uint256 accumulatorPart, uint256 veSdtFeeProxyPart)
        public
        override
    {
        _rewardTokenRepartition[rewardToken] = RewardRepartition(daoPart, accumulatorPart, veSdtFeeProxyPart);
    }
}
