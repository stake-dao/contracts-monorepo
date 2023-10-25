// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {IStrategyVault} from "src/base/interfaces/IStrategyVault.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";
import {IStrategy} from "src/base/interfaces/IStrategy.sol";
import {LibClone} from "solady/utils/LibClone.sol";

/**
 * @title Abstract factory contract used to create LP vaults
 */
abstract contract VaultFactory {
    using LibClone for address;

    error INVALID_GAUGE();
    error GAUGE_ALREADY_USED();

    address public immutable vaultImpl;
    address public immutable gaugeImpl;
    address public constant CLAIM_REWARDS = 0x633120100e108F03aCe79d6C78Aac9a56db1be0F; // v2
    //address public constant GAUGE_IMPL = 0x3Dc56D46F0Bd13655EfB29594a2e44534c453BF9;
    address public constant GOVERNANCE = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;
    address public constant VESDT = 0x0C30476f66034E11782938DF8e4384970B6c9e8a;
    address public constant SDT = 0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F;
    address public constant VEBOOST = 0xD67bdBefF01Fc492f1864E61756E5FBB3f173506;
    IStrategy public immutable strategy;
    address public immutable sdtDistributor;
    uint256 public keeperFee = 100; // 1%

    event VaultDeployed(address proxy, address lptToken, address impl);
    event GaugeDeployed(address proxy, address stakeToken, address impl);

    constructor(address _strategy, address _sdtDistributor, address _vaultImpl, address _gaugeImpl) {
        strategy = IStrategy(_strategy);
        sdtDistributor = _sdtDistributor;
        vaultImpl = _vaultImpl;
        gaugeImpl = _gaugeImpl;
    }

    /**
     * @dev Function to clone a Vault+LG contracts
     * @param _gauge platform gauge
     */
    function cloneAndInit(address _gauge) public virtual {
        // check if the gauge is valid
        if (!_isValidGauge(_gauge)) revert INVALID_GAUGE();
        // check if the lp has been already used to clone a vault
        if (strategy.rewardDistributors(_gauge) != address(0)) revert GAUGE_ALREADY_USED();

        address lp = _getGaugeLp(_gauge);

        (string memory tokenName, string memory tokenSymbol) = _getNameAndSymbol(lp);

        // deploy gauge
        address fakeVault = SDT;
        ILiquidityGaugeStrat sdGauge = _cloneAndInitGauge(gaugeImpl, address(fakeVault), GOVERNANCE, tokenSymbol);
        // deploy vault
        IStrategyVault vault = _cloneAndInitVault(
            vaultImpl,
            lp,
            address(sdGauge),
            GOVERNANCE,
            string(abi.encodePacked("Stake DAO ", tokenName, " Vault")),
            string(abi.encodePacked("sd", tokenSymbol, "-vault"))
        );

        // deploy gauge
        //ILiquidityGaugeStrat sdGauge = _cloneAndInitGauge(gaugeImpl, address(vault), GOVERNANCE, tokenName);

        //vault.setLiquidityGauge(address(sdGauge));
        //vault.transferGovernance(GOVERNANCE);
        strategy.toggleVault(address(vault));
        strategy.setGauge(lp, _gauge);
        strategy.setRewardDistributor(_gauge, address(sdGauge));
        sdGauge.set_claimer(CLAIM_REWARDS);
        sdGauge.set_vault(address(vault));
        _addRewardToGauge();
        //sdGauge.commit_transfer_ownership(GOVERNANCE);
    }

    function _addRewardToGauge() internal virtual {}

    function _isValidGauge(address _gauge) internal virtual view returns (bool) {
        return true;
    }

    function _getGaugeLp(address _gauge) internal virtual view returns (address lp) {
        lp = ILiquidityGaugeStrat(_gauge).lp_token();
    }

    function _getNameAndSymbol(address _lp) internal virtual view returns (string memory name, string memory symbol) {
        name = ERC20(_lp).name();
        symbol = ERC20(_lp).symbol();
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
        address _lpToken,
        address _lg,
        address _governance,
        string memory _name,
        string memory _symbol
    ) internal virtual returns (IStrategyVault deployed) {
        bytes memory data = abi.encodePacked(
            _lpToken, address(strategy), _lg
        );
        deployed = _cloneVault(_impl, _lpToken, keccak256(abi.encodePacked(_governance, _name, _symbol, strategy)), data);
        deployed.initialize();
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
        returns (ILiquidityGaugeStrat deployed)
    {
        deployed = _cloneGauge(_impl, _stakingToken, keccak256(abi.encodePacked(_governance, _symbol)));
        deployed.initialize(_stakingToken, address(this), SDT, VESDT, VEBOOST, sdtDistributor, _stakingToken, _symbol);
    }

    /**
     * @dev Internal function that deploy and returns a clone of vault impl
     * @param _impl address of contract to clone
     * @param _lpToken pendle LPT token address
     * @param _paramsHash governance+name+symbol+strategy parameters hash
     */
    function _cloneVault(address _impl, address _lpToken, bytes32 _paramsHash, bytes memory _data) internal returns (IStrategyVault) {
        address deployed = address(_impl).cloneDeterministic(_data, keccak256(abi.encodePacked(_lpToken, _paramsHash)));
        emit VaultDeployed(deployed, _lpToken, _impl);
        return IStrategyVault(deployed);
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
    // function predictAddress(address _impl, address _token, bytes32 _paramsHash) public view returns (address) {
    //     return address(_impl).predictDeterministicAddress(keccak256(abi.encodePacked(_token, _paramsHash)));
    // }
}
