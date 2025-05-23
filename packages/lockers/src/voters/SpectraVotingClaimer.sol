// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DAO} from "address-book/src/DAOBase.sol";
import {SpectraLocker, SpectraProtocol} from "address-book/src/SpectraBase.sol";
import {AllowanceManager} from "common/governance/AllowanceManager.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {ISpectraVoter} from "src/common/interfaces/spectra/spectra/ISpectraVoter.sol";
import {SafeModule} from "src/common/utils/SafeModule.sol";

interface ISpectraVotingReward {
    function earned(address ve, address token, uint256 tokenId) external view returns (uint256);
    function rewardsListLength() external view returns (uint256);
    function rewards(uint256 i) external view returns (address);
    function getReward(address ve, uint256 tokenId, address[] memory tokens) external;
}

interface ISpectraGovernance {
    function poolsData(uint160 poolId) external view returns (address, uint256, bool);
}

/// @title SpectraVotingClaimer
/// @notice This contract is used to claim all the rewards from the Spectra voting app
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract SpectraVotingClaimer is AllowanceManager, SafeModule {
    using FixedPointMathLib for uint256;

    ////////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    address public immutable SPECTRA_VOTER = SpectraProtocol.VOTER;
    address public immutable SPECTRA_VE_NFT = SpectraProtocol.VESPECTRA;
    address public immutable SPECTRA_GOVERNANCE = SpectraProtocol.GOVERNANCE;
    address public immutable LOCKER = SpectraLocker.LOCKER;

    /// @notice The Stake DAO NFT ID which owns the voting power
    uint256 public immutable SD_SPECTRA_NFT_ID = 1263;

    /// @notice The fee which will be send to SD_TREASURY (10000 = 100%)
    /// @notice Default is 15%
    uint256 public immutable FEE = 1_500;

    /// @notice Denominator for fixed point math.
    uint256 public immutable DENOMINATOR = 10_000;

    /// @notice Stake DAO Treasury
    address public immutable SD_TREASURY = DAO.TREASURY;

    ////////////////////////////////////////////////////////////////
    /// --- STATE
    ///////////////////////////////////////////////////////////////

    /// @notice Address which will receive our funds
    address public recipient;

    ////////////////////////////////////////////////////////////////
    /// --- ERRORS & EVENTS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when a zero address is pass
    error ZERO_ADDRESS();

    /// @notice Error emitted when a balance if wrong after a claim
    error BALANCE_CLAIM();

    /// @notice Error emitted when a balance if wrong after a transfer
    error BALANCE_TRANSFER();

    /// @notice Event emitted when a claim occured
    /// @param tokenAddress Address that was claimed.
    /// @param poolAddress Address that we claimed to.
    /// @param poolId Pool id that we claimed to.
    /// @param chainId The pool chain id.
    /// @param amount Amount claimed.
    /// @param timestamp The claim timestamp
    event Claimed(
        address tokenAddress,
        address poolAddress,
        uint160 poolId,
        uint256 chainId,
        uint256 amount,
        uint256 fees,
        uint256 timestamp
    );

    constructor(address _recipient, address _gateway) AllowanceManager(msg.sender) SafeModule(_gateway) {
        recipient = _recipient;
    }

    ////////////////////////////////////////////////////////////////
    /// --- PUBLIC FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Set a new recipient
    /// @param _newRecipient new recipient address
    /// @custom:throws ZERO_ADDRESS if the recipient is a zero address
    /// @custom:throws NotAuthorized if the caller is not the governance or an allowed address
    function setRecipient(address _newRecipient) external onlyGovernance {
        if (_newRecipient == address(0)) revert ZERO_ADDRESS();
        recipient = _newRecipient;
    }

    /// @notice Check if there is something to claim
    function canClaim() external view returns (bool) {
        ISpectraVoter voter = ISpectraVoter(SPECTRA_VOTER);
        uint256 poolLength = voter.length();

        // 1. check if there is at least one pool to claim
        for (uint256 i; i < poolLength; i++) {
            uint160 poolId = voter.poolIds(i);

            // 1.a check if there are bribes to claim. Return `true` if there is at least one claimable bribe
            address votingRewardAddress = voter.poolToBribe(poolId);
            address[] memory rewardTokens = _getTokenRewards(votingRewardAddress);
            uint256 length = rewardTokens.length;
            for (uint256 a; a < length; a++) {
                if (_earnedAmount(votingRewardAddress, rewardTokens[a]) > 0) return true;
            }

            // 1.b check if there are fees to claim. Return `true` if there is at least one claimable fee
            votingRewardAddress = voter.poolToFees(poolId);
            rewardTokens = _getTokenRewards(votingRewardAddress);
            length = rewardTokens.length;
            for (uint256 a; a < length; a++) {
                if (_earnedAmount(votingRewardAddress, rewardTokens[a]) > 0) return true;
            }
        }

        return false;
    }

    /// @notice Claim pending Spectra voting rewards
    /// @custom:throws ZERO_ADDRESS if the recipient is a zero address
    /// @custom:throws NotAuthorized if the caller is not the governance or an allowed address
    function claim() external onlyGovernance {
        if (recipient == address(0)) revert ZERO_ADDRESS();

        ISpectraVoter voter = ISpectraVoter(SPECTRA_VOTER);
        uint256 poolLength = voter.length();

        for (uint256 i; i < poolLength; i++) {
            uint160 poolId = voter.poolIds(i);

            _claimRewards(voter.poolToBribe(poolId), poolId);
            _claimRewards(voter.poolToFees(poolId), poolId);
        }
    }

    ////////////////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Claim the claimable rewards (bribes or fees) for a given pool
    /// @param votingRewardAddress Address of the voting reward contract
    /// @param poolId Pool id to claim the rewards for
    function _claimRewards(address votingRewardAddress, uint160 poolId) internal {
        address[] memory rewardTokens = _getTokenRewards(votingRewardAddress);
        uint256 length = rewardTokens.length;

        // Check the claimable bribes for each token and claim them if there are any
        for (uint256 a; a < length; a++) {
            address rewardToken = rewardTokens[a];

            uint256 earned = _earnedAmount(votingRewardAddress, rewardToken);
            if (earned == 0) continue;

            _claimAndDistribute(earned, rewardToken, poolId, votingRewardAddress);
        }
    }

    /// @notice Get the earned amount for a given reward token
    /// @param _votingRewardAddress Address of the voting reward contract
    /// @param _rewardToken Address of the reward token
    function _earnedAmount(address _votingRewardAddress, address _rewardToken) internal view returns (uint256 earned) {
        earned = ISpectraVotingReward(_votingRewardAddress).earned(SPECTRA_VE_NFT, _rewardToken, SD_SPECTRA_NFT_ID);
    }

    /// @notice Claim and distribute the claimable rewards for a given pool
    /// @param earned Gross amount to claim
    /// @param rewardToken Token address to claim
    /// @param poolId Pool id to claim the rewards from
    /// @param votingRewardAddress Address of the voting reward contract
    function _claimAndDistribute(uint256 earned, address rewardToken, uint160 poolId, address votingRewardAddress)
        internal
    {
        // Calculate the Stake DAO Treasury fees
        uint256 fees = earned.mulDiv(FEE, DENOMINATOR);

        // Claim the rewards by sending them to the Safe Account (gateway or locker)
        _execute_claim(votingRewardAddress, rewardToken);

        // Remove our fees from what we have to send to the recipient
        earned -= fees;

        // Transfer rewards to the recipient and the Stake DAO Treasury
        _execute_transfer(rewardToken, recipient, earned);
        _execute_transfer(rewardToken, SD_TREASURY, fees);

        // Emit an event to track the claim
        (address poolAddress, uint256 chainId,) = ISpectraGovernance(SPECTRA_GOVERNANCE).poolsData(poolId);
        emit Claimed(rewardToken, poolAddress, poolId, chainId, earned, fees, block.timestamp);
    }

    /// @notice Get all the token rewards associated to a voting reward contract
    /// @param votingRewardAddress Address to the voting reward
    function _getTokenRewards(address votingRewardAddress) internal view returns (address[] memory) {
        ISpectraVotingReward votingReward = ISpectraVotingReward(votingRewardAddress);
        uint256 rewardTokensLength = votingReward.rewardsListLength();

        address[] memory rewardTokens = new address[](rewardTokensLength);

        for (uint256 i; i < rewardTokensLength; i++) {
            rewardTokens[i] = votingReward.rewards(i);
        }

        return rewardTokens;
    }

    /// @notice Send a transaction to the safe to claim voting rewards
    /// @dev Should be called only by the owner
    /// @param votingRewardAddress Address to the voting reward where the claim will happened
    /// @param reward Reward address to claim
    function _execute_claim(address votingRewardAddress, address reward) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = reward;

        bytes memory data =
            abi.encodeWithSelector(ISpectraVotingReward.getReward.selector, SPECTRA_VE_NFT, SD_SPECTRA_NFT_ID, tokens);

        _executeTransaction(votingRewardAddress, data);
    }

    /// @notice Send some tokens to an address
    /// @param token Token address to transfer
    /// @param to Address to transfer the tokens to
    /// @param amount Amount to transfer
    function _execute_transfer(address token, address to, uint256 amount) internal {
        _executeTransaction(token, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
    }

    /// @notice Get the locker address
    /// @dev Must be implemented for the SafeModule contract
    function _getLocker() internal view override returns (address) {
        return LOCKER;
    }
}
