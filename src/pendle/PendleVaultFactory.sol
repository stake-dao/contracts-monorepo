// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "../base/interfaces/IGaugeController.sol";
import "../base/interfaces/ILiquidityGaugeStrat.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

interface IPendleMarketFactory {
    function isValidMarket(address) external returns (bool);
}

interface IPendleLp {
    function readTokens() external view returns (address, address, address);
}

interface PendleStrategy {
    function toggleVault(address _vault) external;
    function setSdGauge(address _token, address _sdGauge) external;
    function sdGauges(address) external view returns (address);
}

interface PendleVault {
    function init(
        ERC20Upgradeable _token,
        address _governance,
        string memory name_,
        string memory symbol_,
        PendleStrategy _pendleStrategy
    ) external;

    function setLiquidityGauge(address _liquidityGauge) external;

    function setGovernance(address _governance) external;
}
/**
 * @title Factory contract usefull for creating new pendle LPT vaults
 * to the pendle platform, and the gauge multi rewards attached to it.
 */

contract PendleVaultFactory {
    using ClonesUpgradeable for address;

    error NOT_MARKET();

    address public vaultImpl = 0x44A6A278A9a55fF22Fd5F7c6fe84af916396470C; // Deployed vault implementation
    address public constant CLAIM_REWARDS = 0x633120100e108F03aCe79d6C78Aac9a56db1be0F; // v2
    address public constant GOVERNANCE = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;
    address public constant PENDLE = 0x808507121B80c02388fAd14726482e061B8da827;
    address public constant VESDT = 0x0C30476f66034E11782938DF8e4384970B6c9e8a;
    address public constant SDT = 0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F;
    address public constant VEBOOST = 0xD67bdBefF01Fc492f1864E61756E5FBB3f173506;
    address public constant PENDLE_MARKET_FACTORY_V3 = 0x1A6fCc85557BC4fB7B534ed835a03EF056552D52; // v3 factory

    address public strategy;
    address public sdtDistributor;
    address public gaugeImpl = 0x3Dc56D46F0Bd13655EfB29594a2e44534c453BF9;

    event VaultDeployed(address proxy, address lptToken, address impl);
    event GaugeDeployed(address proxy, address stakeToken, address impl);

    constructor(address _strategy, address _sdtDistributor, address _gaugeImpl) {
        strategy = _strategy;
        sdtDistributor = _sdtDistributor;
        gaugeImpl = _gaugeImpl;
    }

    /**
     * @dev Function to clone a Pendle Vault and its gauge contracts
     * @param _pendleLpt Pendle Lpt market address
     */
    function cloneAndInit(address _pendleLpt) public {
        if (!IPendleMarketFactory(PENDLE_MARKET_FACTORY_V3).isValidMarket(_pendleLpt)) revert NOT_MARKET();

        (, address ptToken,) = IPendleLp(_pendleLpt).readTokens();
        string memory tokenName = string(abi.encodePacked("L", ERC20Upgradeable(ptToken).name()));
        address vault = _cloneAndInitVault(
            vaultImpl,
            ERC20Upgradeable(_pendleLpt),
            GOVERNANCE,
            string(abi.encodePacked("Stake DAO ", tokenName, " Vault")),
            string(abi.encodePacked("sd", tokenName, "-vault"))
        );
        address gauge = _cloneAndInitGauge(gaugeImpl, vault, GOVERNANCE, tokenName);
        PendleVault(vault).setLiquidityGauge(gauge);
        PendleVault(vault).setGovernance(GOVERNANCE);
        PendleStrategy(strategy).toggleVault(vault);
        PendleStrategy(strategy).setSdGauge(_pendleLpt, gauge);
        ILiquidityGaugeStrat(gauge).add_reward(PENDLE, strategy);
        ILiquidityGaugeStrat(gauge).set_claimer(CLAIM_REWARDS);
        ILiquidityGaugeStrat(gauge).commit_transfer_ownership(GOVERNANCE);
    }

    /**
     * @dev Internal function to clone the vault
     * @param _impl address of contract to clone
     * @param _lpToken Pendle LPT token address
     * @param _governance governance address
     * @param _name vault name
     * @param _symbol vault symbol
     */
    function _cloneAndInitVault(
        address _impl,
        ERC20Upgradeable _lpToken,
        address _governance,
        string memory _name,
        string memory _symbol
    ) internal returns (address) {
        PendleVault deployed =
            _cloneVault(_impl, _lpToken, keccak256(abi.encodePacked(_governance, _name, _symbol, strategy)));
        deployed.init(_lpToken, address(this), _name, _symbol, PendleStrategy(strategy));
        return address(deployed);
    }

    /**
     * @dev Internal function to clone the gauge multi rewards
     * @param _impl address of contract to clone
     * @param _stakingToken sd LP token address
     * @param _governance governance address
     * @param _symbol gauge symbol
     */
    function _cloneAndInitGauge(address _impl, address _stakingToken, address _governance, string memory _symbol)
        internal
        returns (address)
    {
        ILiquidityGaugeStrat deployed =
            _cloneGauge(_impl, _stakingToken, keccak256(abi.encodePacked(_governance, _symbol)));
        deployed.initialize(_stakingToken, address(this), SDT, VESDT, VEBOOST, sdtDistributor, _stakingToken, _symbol);
        return address(deployed);
    }

    /**
     * @dev Internal function that deploy and returns a clone of vault impl
     * @param _impl address of contract to clone
     * @param _lpToken pendle LPT token address
     * @param _paramsHash governance+name+symbol+strategy parameters hash
     */
    function _cloneVault(address _impl, ERC20Upgradeable _lpToken, bytes32 _paramsHash)
        internal
        returns (PendleVault)
    {
        address deployed =
            address(_impl).cloneDeterministic(keccak256(abi.encodePacked(address(_lpToken), _paramsHash)));
        emit VaultDeployed(deployed, address(_lpToken), _impl);
        return PendleVault(deployed);
    }

    /**
     * @dev Internal function that deploy and returns a clone of gauge impl
     * @param _impl address of contract to clone
     * @param _stakingToken sd LP token address
     * @param _paramsHash governance+name+symbol parameters hash
     */
    function _cloneGauge(address _impl, address _stakingToken, bytes32 _paramsHash)
        internal
        returns (ILiquidityGaugeStrat)
    {
        address deployed =
            address(_impl).cloneDeterministic(keccak256(abi.encodePacked(address(_stakingToken), _paramsHash)));
        emit GaugeDeployed(deployed, _stakingToken, _impl);
        return ILiquidityGaugeStrat(deployed);
    }

    /**
     * @dev Function that predicts the future address passing the parameters
     * @param _impl address of contract to clone
     * @param _token token (LP or sdLP)
     * @param _paramsHash parameters hash
     */
    function predictAddress(address _impl, IERC20 _token, bytes32 _paramsHash) public view returns (address) {
        return address(_impl).predictDeterministicAddress(keccak256(abi.encodePacked(address(_token), _paramsHash)));
    }
}
