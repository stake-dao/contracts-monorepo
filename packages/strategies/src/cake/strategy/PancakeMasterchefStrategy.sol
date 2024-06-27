// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {ERC721} from "solady/tokens/ERC721.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {ILocker} from "src/base/interfaces/ILocker.sol";
import {ICakeNfpm} from "src/base/interfaces/ICakeNfpm.sol";
import {IExecutor} from "src/base/interfaces/IExecutor.sol";
import {SafeExecute} from "src/base/libraries/SafeExecute.sol";

/// @notice Main access point of Cake Locker.
contract PancakeMasterchefStrategy is ReentrancyGuard, UUPSUpgradeable {
    using FixedPointMathLib for uint256;
    using SafeExecute for ILocker;
    using SafeTransferLib for ERC20;

    struct CollectedFees {
        uint256 token0Amount;
        uint256 token1Amount;
    }

    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Address of the locker contract.
    ILocker public immutable locker;

    /// @notice PancakeSwap masterChef.
    address public immutable masterchef;

    /// @notice Address of the token being rewarded.
    address public immutable rewardToken;

    /// @notice PancakeSwap non fungible position manager.
    address public immutable nonFungiblePositionManager;

    /// @notice Address of the executor contract.
    IExecutor public executor;

    /// @notice Address of the governance.
    address public governance;

    /// @notice Address of the future governance contract.
    address public futureGovernance;

    /// @notice Address accruing protocol fees.
    address public feeReceiver;

    /// @notice Percentage of fees charged on `rewardToken` claimed.
    uint256 public protocolFeesPercent;

    /// @notice Amount of fees charged on `rewardToken` claimed
    uint256 public feesAccrued;

    /// @notice Reward claimer.
    address public rewardClaimer;

    /// @notice Mapping of User -> TokenId
    mapping(uint256 => address) public positionOwner; // tokenId -> user

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted at every fee collected by stakers.
    /// @param token0 Address of token0.
    /// @param token1 Address of token1.
    /// @param token0Collected Amount of token0 collected.
    /// @param token1Collected Amount of token1 collected.
    event FeeCollected(
        address indexed token0, address indexed token1, uint256 token0Collected, uint256 token1Collected
    );

    /// @notice Event emitted when governance is changed.
    /// @param newGovernance Address of the new governance.
    event GovernanceChanged(address newGovernance);

    /// @notice Event emitted when the fees are claimed
    /// @param feeReceiver fee receiver
    /// @param feeClaimed amount of fees claimed
    event ProtocolFeeClaimed(address indexed feeReceiver, uint256 feeClaimed);

    /// @notice Event emitted at every harvest
    /// @param tokenId nft id harvested for
    /// @param amount amount harvested
    /// @param recipient reward recipient
    event Harvest(uint256 indexed tokenId, uint256 amount, address recipient);

    /// @notice Error emitted when input address is null
    error AddressNull();

    /// @notice Error emitted when call failed
    error CallFailed();

    /// @notice Error emitted when auth failed
    error Governance();

    /// @notice Error emitted when sum of fees is above 100%
    error FeeTooHigh();

    /// @notice throwed when the ERC721 hook has not called by cake nfpm
    error NotPancakeNFT();

    /// @notice Error emitted when auth failed
    error Unauthorized();

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    modifier onlyPositionOwner(uint256 tokenId) {
        if (msg.sender != positionOwner[tokenId]) revert Unauthorized();
        _;
    }

    modifier onlyPositionOwnerOrClaimer(uint256[] memory tokenIds) {
        if (msg.sender != rewardClaimer) {
            for (uint256 i; i < tokenIds.length;) {
                if (msg.sender != positionOwner[tokenIds[i]]) revert Unauthorized();
                unchecked {
                    ++i;
                }
            }
        }
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert Unauthorized();
        _;
    }

    /// @notice Constructor.
    /// @param _governance Address of the strategy governance.
    /// @param _locker Address of the locker.
    /// @param _rewardToken Address of the reward token.
    constructor(address _governance, address _locker, address _rewardToken) {
        governance = _governance;
        locker = ILocker(_locker);
        rewardToken = _rewardToken;

        masterchef = 0x556B9306565093C855AEA9AE92A594704c2Cd59e; // v3
        nonFungiblePositionManager = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    }

    /// @notice Initialize function.
    /// @param _governance Address of the governance.
    /// @param _executor Address of the executor.
    function initialize(address _governance, address _executor) external {
        if (governance != address(0)) revert AddressNull();
        governance = _governance;
        executor = IExecutor(_executor);
    }

    /// @notice Harvest reward for NFTs.
    /// @param _tokenIds NFT ids to harvest.
    /// @param _recipient Address of the recipient.
    function harvestRewards(uint256[] memory _tokenIds, address _recipient)
        external
        nonReentrant
        onlyPositionOwnerOrClaimer(_tokenIds)
        returns (uint256[] memory)
    {
        uint256 tokensLength = _tokenIds.length;
        uint256[] memory rewards = new uint256[](tokensLength);
        for (uint256 i; i < tokensLength;) {
            rewards[i] = _harvestReward(_tokenIds[i], _recipient);
            unchecked {
                ++i;
            }
        }
        return rewards;
    }

    /// @notice Harvest fees for NFTs.
    /// @param _tokenIds NFT ids to harvest fees for.
    /// @param _recipient Address of the recipient.
    function collectFees(uint256[] memory _tokenIds, address _recipient)
        external
        nonReentrant
        onlyPositionOwnerOrClaimer(_tokenIds)
        returns (CollectedFees[] memory _collected)
    {
        uint256 tokensLength = _tokenIds.length;
        _collected = new CollectedFees[](tokensLength);

        uint256 token0Collected;
        uint256 token1Collected;
        for (uint256 i; i < tokensLength;) {
            (token0Collected, token1Collected) = (_collectFee(_tokenIds[i], _recipient));
            _collected[i] = CollectedFees(token0Collected, token1Collected);

            unchecked {
                i++;
            }
        }
    }

    /// @notice Harvest both reward and fees for NFTs.
    /// @param _tokenIds NFT ids to harvest.
    function harvestAndCollectFees(uint256[] memory _tokenIds, address _recipient)
        external
        nonReentrant
        onlyPositionOwnerOrClaimer(_tokenIds)
        returns (uint256[] memory _rewards, CollectedFees[] memory _collected)
    {
        uint256 tokenLength = _tokenIds.length;
        _rewards = new uint256[](tokenLength);
        _collected = new CollectedFees[](tokenLength);

        uint256 token0Collected;
        uint256 token1Collected;

        for (uint256 i; i < tokenLength;) {
            _rewards[i] = _harvestReward(_tokenIds[i], _recipient);
            (token0Collected, token1Collected) = _collectFee(_tokenIds[i], _recipient);
            _collected[i] = CollectedFees(token0Collected, token1Collected);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Withdraw the NFT sending it to the recipient.
    /// @param _tokenId NFT id to withdraw.
    function withdraw(uint256 _tokenId) external nonReentrant returns (uint256 reward) {
        reward = _withdraw(_tokenId, msg.sender);
    }

    /// @notice Withdraw the NFT sending it to the recipient.
    /// @param _tokenId NFT id to withdraw.
    /// @param _recipient NFT receiver.
    function withdraw(uint256 _tokenId, address _recipient) external nonReentrant returns (uint256 reward) {
        reward = _withdraw(_tokenId, _recipient);
    }

    /// @notice Hook triggered within safe function calls.
    /// @param _from NFT sender.
    /// @param _tokenId NFT id received
    function onERC721Received(address, address _from, uint256 _tokenId, bytes calldata) external returns (bytes4) {
        if (msg.sender != nonFungiblePositionManager) revert NotPancakeNFT();
        if (_from == masterchef) return this.onERC721Received.selector;

        // store the owner's tokenId
        positionOwner[_tokenId] = _from;

        // transfer the NFT to the cake locker using the non safe transfer to not trigger the hook
        ERC721(nonFungiblePositionManager).transferFrom(address(this), address(locker), _tokenId);

        // transfer the NFT to the pancake masterchef v3 via the locker using safe transfer to trigger the hook
        bytes memory safeTransferData =
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", address(locker), masterchef, _tokenId);
        (bool success,) = executor.callExecuteTo(address(locker), nonFungiblePositionManager, 0, safeTransferData);
        if (!success) revert CallFailed();

        return this.onERC721Received.selector;
    }

    /// @notice Decrease NFT Position Liquidity.
    /// @param _tokenId nft token id.
    /// @param _liquidity new liquidity
    /// @param _amount0Min min amount to receive of token0
    /// @param _amount1Min min amount to receive of token1
    function decreaseLiquidity(
        uint256 _tokenId,
        uint128 _liquidity,
        uint256 _amount0Min,
        uint256 _amount1Min,
        uint256 _deadline
    ) external nonReentrant onlyPositionOwner(_tokenId) returns (uint256 amount0, uint256 amount1) {
        bytes memory decreaseLiqData = abi.encodeWithSignature(
            "decreaseLiquidity((uint256,uint128,uint256,uint256,uint256))",
            _tokenId,
            _liquidity,
            _amount0Min,
            _amount1Min,
            _deadline
        );

        (bool success, bytes memory result) = executor.callExecuteTo(address(locker), masterchef, 0, decreaseLiqData);
        if (!success) revert CallFailed();

        (amount0, amount1) = abi.decode(result, (uint256, uint256));

        // collect liquidity removed
        _collectFee(_tokenId, msg.sender);
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Internal function to harvest reward for an NFT.
    /// @param _tokenId NFT id to harvest.
    /// @param _recipient reward recipient
    function _harvestReward(uint256 _tokenId, address _recipient) internal returns (uint256 reward) {
        bytes memory harvestData = abi.encodeWithSignature("harvest(uint256,address)", _tokenId, address(this));
        (bool success, bytes memory result) = executor.callExecuteTo(address(locker), masterchef, 0, harvestData);
        if (!success) revert CallFailed();

        reward = abi.decode(result, (uint256));

        if (reward != 0) {
            // charge fee
            reward -= _chargeProtocolFees(reward);
            // send the reward - fees to the recipient
            SafeTransferLib.safeTransfer(rewardToken, _recipient, reward);

            emit Harvest(_tokenId, reward, _recipient);
        }
    }

    /// @notice Internal function to collect fee for an NFT.
    /// @param _tokenId NFT id to collect fee for.
    /// @param _recipient reward recipient
    function _collectFee(uint256 _tokenId, address _recipient) internal returns (uint256, uint256) {
        // fetch underlying tokens
        (,, address token0, address token1,,,,,,,,) = ICakeNfpm(nonFungiblePositionManager).positions(_tokenId);

        // collect fees if there is any and transfer here
        bytes memory harvestData = abi.encodeWithSignature(
            "collect((uint256,address,uint128,uint128))", _tokenId, address(this), type(uint128).max, type(uint128).max
        );
        (bool success, bytes memory result) = executor.callExecuteTo(address(locker), masterchef, 0, harvestData);
        if (!success) revert CallFailed();

        (uint256 token0Collected, uint256 token1Collected) = abi.decode(result, (uint256, uint256));

        // transfer token0 collected to the recipient
        if (token0Collected != 0) {
            SafeTransferLib.safeTransfer(token0, _recipient, token0Collected);
        }

        // transfer token1 collected to the recipient
        if (token1Collected != 0) {
            SafeTransferLib.safeTransfer(token1, _recipient, token1Collected);
        }

        emit FeeCollected(token0, token1, token0Collected, token1Collected);

        return (token0Collected, token1Collected);
    }

    /// @notice Internal function to withdraw the NFT sending it to the recipient.
    /// @param _tokenId NFT id to withdraw.
    /// @param _recipient NFT recipient
    function _withdraw(uint256 _tokenId, address _recipient)
        internal
        onlyPositionOwner(_tokenId)
        returns (uint256 reward)
    {
        // withdraw the NFT from pancake masterchef, sending it + rewards if any to this contract
        // it charges fees on the reward and then send the NFT + reward - fees to the _recipient
        bytes memory withdrawData = abi.encodeWithSignature("withdraw(uint256,address)", _tokenId, address(this));
        (bool success, bytes memory result) = executor.callExecuteTo(address(locker), masterchef, 0, withdrawData);
        if (!success) revert CallFailed();

        reward = abi.decode(result, (uint256));

        if (reward != 0) {
            // charge fee
            reward -= _chargeProtocolFees(reward);
            // send the reward - fees to the recipient
            SafeTransferLib.safeTransfer(rewardToken, _recipient, reward);
        }

        ERC721(nonFungiblePositionManager).safeTransferFrom(address(this), _recipient, _tokenId);

        delete positionOwner[_tokenId];
    }

    /// @notice Internal function to increase the allowance if needed
    /// @param _token Token to appprove
    /// @param _amount Allowance amount required
    function _approveIfNeeded(address _token, uint256 _amount) internal {
        if (ERC20(_token).allowance(address(this), masterchef) < _amount) {
            SafeTransferLib.safeApprove(_token, masterchef, type(uint256).max);
        }
    }

    //////////////////////////////////////////////////////
    /// --- PROTOCOL FEES ACCOUNTING
    //////////////////////////////////////////////////////

    /// @notice Claim protocol fees and send them to the fee receiver.
    function claimProtocolFees() external {
        if (feesAccrued == 0) return;
        if (feeReceiver == address(0)) revert AddressNull();

        uint256 _feesAccrued = feesAccrued;
        feesAccrued = 0;

        SafeTransferLib.safeTransfer(rewardToken, feeReceiver, _feesAccrued);

        emit ProtocolFeeClaimed(feeReceiver, _feesAccrued);
    }

    /// @notice Internal function to charge protocol fees from `rewardToken` claimed by the locker.
    /// @return _amount Amount left after charging protocol fees.
    function _chargeProtocolFees(uint256 amount) internal returns (uint256) {
        if (amount == 0 || protocolFeesPercent == 0) return 0;

        uint256 _feeAccrued = amount.mulDiv(protocolFeesPercent, DENOMINATOR);
        feesAccrued += _feeAccrued;

        return _feeAccrued;
    }

    //////////////////////////////////////////////////////
    /// --- GOVERNANCE STRATEGY SETTERS
    //////////////////////////////////////////////////////

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert Governance();

        governance = msg.sender;
        futureGovernance = address(0);

        emit GovernanceChanged(msg.sender);
    }

    /// @notice Set FeeReceiver new address.
    /// @param _feeReceiver Address of new FeeReceiver.
    function setFeeReceiver(address _feeReceiver) external onlyGovernance {
        if (_feeReceiver == address(0)) revert AddressNull();
        feeReceiver = _feeReceiver;
    }

    /// @notice Set Executor new address.
    /// @param _executor Address of new executor.
    function setExecutor(address _executor) external onlyGovernance {
        executor = IExecutor(_executor);
    }

    /// @notice Set reward claimer.
    /// @param _rewardClaimer Address of the claimer.
    function setRewardClaimer(address _rewardClaimer) external onlyGovernance {
        rewardClaimer = _rewardClaimer;
    }

    /// @notice Update protocol fees.
    /// @param protocolFee New protocol fee.
    function updateProtocolFee(uint256 protocolFee) external onlyGovernance {
        if (protocolFee > DENOMINATOR) revert FeeTooHigh();
        protocolFeesPercent = protocolFee;
    }

    //////////////////////////////////////////////////////
    /// --- GOVERNANCE OR ALLOWED FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Execute a function.
    /// @param to Address of the contract to execute.
    /// @param value Value to send to the contract.
    /// @param data Data to send to the contract.
    /// @return success_ Boolean indicating if the execution was successful.
    /// @return result_ Bytes containing the result of the execution.
    function execute(address to, uint256 value, bytes calldata data)
        external
        onlyGovernance
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = to.call{value: value}(data);
        return (success, result);
    }

    /// UUPS Upgradeability.
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    receive() external payable {}
}
