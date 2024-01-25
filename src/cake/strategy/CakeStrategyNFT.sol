// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {ERC721} from "solady/tokens/ERC721.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {ICakeNfpm} from "src/base/interfaces/ICakeNfpm.sol";
import {IExecutor} from "src/base/interfaces/IExecutor.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {SafeExecute} from "src/base/libraries/SafeExecute.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";

/// @notice Main access point of Cake Locker.
contract CakeStrategyNFT is UUPSUpgradeable {
    using FixedPointMathLib for uint256;
    using SafeExecute for ILocker;
    using SafeTransferLib for ERC20;

    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice collect() signature string
    string public constant COLLECT_SIG = "collect((uint256,address,uint128,uint128))";

    /// @notice decreaseLiquidity() signature string
    string public constant DECREASE_LIQ_SIG = "decreaseLiquidity((uint256,uint128,uint256,uint256,uint256))";

    /// @notice harvest() signature string
    string public constant HARVEST_SIG = "harvest(uint256,address)";

    /// @notice increaseLiquidity() signature string
    string public constant INCREASE_LIQ_SIG = "increaseLiquidity((uint256,uint256,uint256,uint256,uint256,uint256))";

    /// @notice safeTransferFrom() signature string
    string public constant SAFE_TRANSFER_SIG = "safeTransferFrom(address,address,uint256)";

    /// @notice withdraw() signature string
    string public constant WITHDRAW_SIG = "withdraw(uint256,address)";

    /// @notice Address of the locker contract.
    ILocker public immutable locker;

    /// @notice Address of the token being rewarded.
    address public immutable rewardToken;

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

    /// @notice PancakeSwap non fungible position manager.
    address public cakeNfpm;

    /// @notice PancakeSwap masterChef.
    address public cakeMc;

    /// @notice Reward claimer.
    address public rewardClaimer;

    /// @notice Increase liq deadline -> block.timestamp + deadlinePeriod
    uint256 public deadlinePeriod = 1 hours;

    /// @notice Mapping of NFT stakers.
    mapping(uint256 => address) public nftStakers; // tokenId -> user

    /// @notice Map addresses allowed to interact with the `execute` function.
    mapping(address => bool) public allowed;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when governance is changed.
    /// @param newGovernance Address of the new governance.
    event GovernanceChanged(address newGovernance);

    /// @notice Event emitted when the fees are claimed
    /// @param feeReceiver fee receiver
    /// @param feeClaimed amount of fees claimed
    event FeeClaimed(address indexed feeReceiver, uint256 feeClaimed);

    /// @notice Event emitted at every harvest
    /// @param tokenId nft id harvested for
    /// @param amount amount harvested
    /// @param recipient reward recipient
    event Harvest(uint256 indexed tokenId, uint256 amount, address recipient);

    /// @notice Event emitted when an Nft is deposited via the safe transfer hook
    /// @param tokenId nft id deposited
    /// @param staker nft staker
    event NftDeposited(uint256 indexed tokenId, address indexed staker);

    /// @notice Event emitted when an Nft is withdrawn
    /// @param tokenId nft id withdrawn
    /// @param recipient nft recipient
    event NftWithdrawn(uint256 indexed tokenId, address indexed recipient);

    /// @notice Error emitted when input address is null
    error AddressNull();

    /// @notice Error emitted when call failed
    error CallFailed();

    /// @notice Error emitted when auth failed
    error Governance();

    /// @notice Error emitted when sum of fees is above 100%
    error FeeTooHigh();

    /// @notice Error emitted when trying to allow an EOA.
    error NotContract();

    /// @notice throwed when the ERC721 hook has not called by cake nfpm
    error NotPancakeNFT();

    /// @notice Error emitted when auth failed
    error Unauthorized();

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    modifier onlyNftStaker(uint256 tokenId) {
        if (msg.sender != nftStakers[tokenId]) revert Unauthorized();
        _;
    }

    modifier onlyNftStakerOrClaimer(uint256 tokenId) {
        if (msg.sender != nftStakers[tokenId] && msg.sender != rewardClaimer) revert Unauthorized();
        _;
    }

    modifier onlyNftsStakerOrClaimer(uint256[] memory tokenIds) {
        if (msg.sender != rewardClaimer) {
            for (uint256 i; i < tokenIds.length;) {
                if (msg.sender != nftStakers[tokenIds[i]]) revert Unauthorized();
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

    modifier onlyGovernanceOrAllowed() {
        if (msg.sender != governance && !allowed[msg.sender]) revert Unauthorized();
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
    }

    /// @notice Initialize function.
    /// @param _governance Address of the governance.
    /// @param _executor Address of the executor.
    function initialize(address _governance, address _executor) external {
        if (governance != address(0)) revert AddressNull();
        governance = _governance;
        executor = IExecutor(_executor);

        cakeMc = 0x556B9306565093C855AEA9AE92A594704c2Cd59e; // v3
        cakeNfpm = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    }

    /// @notice Harvest reward for an NFT.
    /// @param _tokenId NFT id to harvest.
    /// @param _recipient Address of the recipient.
    function harvestReward(uint256 _tokenId, address _recipient) external onlyNftStakerOrClaimer(_tokenId) {
        _harvestReward(_tokenId, _recipient);
    }

    /// @notice Harvest reward for NFTs.
    /// @param _tokenIds NFT ids to harvest.
    /// @param _recipient Address of the recipient.
    function harvestRewards(uint256[] memory _tokenIds, address _recipient)
        external
        onlyNftsStakerOrClaimer(_tokenIds)
    {
        uint256 tokensLength = _tokenIds.length;
        for (uint256 i; i < tokensLength;) {
            _harvestReward(_tokenIds[i], _recipient);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Collect fee for NFT.
    /// @param _tokenId NFT id to collect fee for.
    /// @param _recipient Address of the recipient.
    function collectFee(uint256 _tokenId, address _recipient) external onlyNftStakerOrClaimer(_tokenId) {
        _collectFee(_tokenId, _recipient);
    }

    /// @notice Harvest fees for NFTs.
    /// @param _tokenIds NFT ids to harvest fees for.
    /// @param _recipient Address of the recipient.
    function collectFees(uint256[] memory _tokenIds, address _recipient) external onlyNftsStakerOrClaimer(_tokenIds) {
        uint256 tokensLength = _tokenIds.length;
        for (uint256 i; i < tokensLength;) {
            _collectFee(_tokenIds[i], _recipient);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Harvest both reward and fees for NFT.
    /// @param _tokenId NFT id to harvest.
    function harvestAndCollectFee(uint256 _tokenId, address _recipient) external onlyNftStakerOrClaimer(_tokenId) {
        _harvestReward(_tokenId, _recipient);
        _collectFee(_tokenId, _recipient);
    }

    /// @notice Harvest both reward and fees for NFTs.
    /// @param _tokenIds NFT ids to harvest.
    function harvestAndCollectFees(uint256[] memory _tokenIds, address _recipient)
        external
        onlyNftsStakerOrClaimer(_tokenIds)
    {
        uint256 tokenLength = _tokenIds.length;
        for (uint256 i; i < tokenLength;) {
            _harvestReward(_tokenIds[i], _recipient);
            _collectFee(_tokenIds[i], _recipient);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Withdraw the NFT sending it to the recipient.
    /// @param _tokenId NFT id to withdraw.
    function withdrawNft(uint256 _tokenId) external {
        _withdrawNft(_tokenId, msg.sender);
    }

    /// @notice Withdraw the NFT sending it to the recipient.
    /// @param _tokenId NFT id to withdraw.
    /// @param _recipient NFT receiver.
    function withdrawNft(uint256 _tokenId, address _recipient) external {
        _withdrawNft(_tokenId, _recipient);
    }

    /// @notice Hook triggered within safe function calls.
    /// @param _from NFT sender.
    /// @param _tokenId NFT id received
    function onERC721Received(address, address _from, uint256 _tokenId, bytes calldata) external returns (bytes4) {
        if (msg.sender != cakeNfpm) revert NotPancakeNFT();

        // store the owner's tokenId
        nftStakers[_tokenId] = _from;

        // transfer the NFT to the cake locker using the non safe transfer to not trigger the hook
        ERC721(cakeNfpm).transferFrom(address(this), address(locker), _tokenId);

        // transfer the NFT to the pancake masterchef v3 via the locker using safe transfer to trigger the hook
        bytes memory safeTransferData = abi.encodeWithSignature(SAFE_TRANSFER_SIG, address(locker), cakeMc, _tokenId);
        (bool success,) = executor.callExecuteTo(address(locker), cakeNfpm, 0, safeTransferData);
        if (!success) revert CallFailed();

        emit NftDeposited(_tokenId, _from);

        return this.onERC721Received.selector;
    }

    /// @notice Increase NFT Position Liquidity.
    /// @param _tokenId nft token id.
    /// @param _amount0Desired amount to add of token0
    /// @param _amount1Desired amount to add of token1
    /// @param _amount0Min min amount to add of token0
    /// @param _amount1Min min amount to add of token1
    function increaseLiquidity(
        uint256 _tokenId,
        uint256 _amount0Desired,
        uint256 _amount1Desired,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external {
        // fetch underlying tokens
        (,, address token0, address token1,,,,,,,,) = ICakeNfpm(cakeNfpm).positions(_tokenId);

        // transfer token here
        SafeTransferLib.safeTransferFrom(token0, msg.sender, address(this), _amount0Desired);
        SafeTransferLib.safeTransferFrom(token1, msg.sender, address(this), _amount1Desired);

        _approveIfNeeded(token0, _amount0Desired);
        _approveIfNeeded(token1, _amount1Desired);
        bytes memory increaseLiqData = abi.encodeWithSignature(
            INCREASE_LIQ_SIG,
            _tokenId,
            _amount0Desired,
            _amount1Desired,
            _amount0Min,
            _amount1Min,
            block.timestamp + deadlinePeriod // deadline
        );
        (bool success,) = cakeMc.call(increaseLiqData);
        if (!success) revert CallFailed();
    }

    /// @notice Decrease NFT Position Liquidity.
    /// @param _tokenId nft token id.
    /// @param _liquidity new liquidity
    /// @param _amount0Min min amount to receive of token0
    /// @param _amount1Min min amount to receive of token1
    function decreaseLiquidity(uint256 _tokenId, uint128 _liquidity, uint256 _amount0Min, uint256 _amount1Min)
        external
        onlyNftStaker(_tokenId)
    {
        bytes memory decreaseLiqData = abi.encodeWithSignature(
            DECREASE_LIQ_SIG, _tokenId, _liquidity, _amount0Min, _amount1Min, block.timestamp + 1 hours
        );
        (bool success,) = executor.callExecuteTo(address(locker), cakeMc, 0, decreaseLiqData);
        if (!success) revert CallFailed();

        // collect liquidity removed
        _collectFee(_tokenId, msg.sender);
    }

    /// @notice Internal function to harvest reward for an NFT.
    /// @param _tokenId NFT id to harvest.
    /// @param _recipient reward recipient
    function _harvestReward(uint256 _tokenId, address _recipient) internal {
        uint256 balanceBeforeHarvest = ERC20(rewardToken).balanceOf(address(this));

        bytes memory harvestData = abi.encodeWithSignature(HARVEST_SIG, _tokenId, address(this));
        (bool success,) = executor.callExecuteTo(address(locker), cakeMc, 0, harvestData);
        if (!success) revert CallFailed();

        uint256 reward = ERC20(rewardToken).balanceOf(address(this)) - balanceBeforeHarvest;

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
    function _collectFee(uint256 _tokenId, address _recipient) internal {
        // fetch underlying tokens
        (,, address token0, address token1,,,,,,,,) = ICakeNfpm(cakeNfpm).positions(_tokenId);
        uint256 token0BalanceBeforeCollect = ERC20(token0).balanceOf(address(this));
        uint256 token1BalanceBeforeCollect = ERC20(token1).balanceOf(address(this));

        // collect fees if there is any and transfer here
        bytes memory harvestData =
            abi.encodeWithSignature(COLLECT_SIG, _tokenId, address(this), type(uint128).max, type(uint128).max);
        (bool success,) = executor.callExecuteTo(address(locker), cakeMc, 0, harvestData);
        if (!success) revert CallFailed();

        // transfer token0 collected to the recipient
        uint256 token0Collected = ERC20(token0).balanceOf(address(this)) - token0BalanceBeforeCollect;
        if (token0Collected != 0) {
            SafeTransferLib.safeTransfer(token0, _recipient, token0Collected);
        }

        // transfer token1 collected to the recipient
        uint256 token1Collected = ERC20(token1).balanceOf(address(this)) - token1BalanceBeforeCollect;
        if (token1Collected != 0) {
            SafeTransferLib.safeTransfer(token1, _recipient, token1Collected);
        }
    }

    /// @notice Internal function to withdraw the NFT sending it to the recipient.
    /// @param _tokenId NFT id to withdraw.
    /// @param _recipient NFT recipient
    function _withdrawNft(uint256 _tokenId, address _recipient) internal onlyNftStaker(_tokenId) {
        // withdraw the NFT from pancake masterchef, it will send it to the recipient
        // if there is any reward to collect it will be send to the recipient
        bytes memory withdrawData = abi.encodeWithSignature(WITHDRAW_SIG, _tokenId, _recipient);
        (bool success,) = executor.callExecuteTo(address(locker), cakeMc, 0, withdrawData);
        if (!success) revert CallFailed();

        delete nftStakers[_tokenId];

        emit NftWithdrawn(_tokenId, _recipient);
    }

    /// @notice Internal function to increase the allowance if needed
    /// @param _token Token to appprove
    /// @param _amount Allowance amount required
    function _approveIfNeeded(address _token, uint256 _amount) internal {
        if (ERC20(_token).allowance(address(this), cakeMc) < _amount) {
            SafeTransferLib.safeApprove(_token, cakeMc, type(uint256).max);
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

        emit FeeClaimed(feeReceiver, _feesAccrued);
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
        emit GovernanceChanged(msg.sender);
    }

    /// @notice Set pancake masterchef.
    /// @param _cakeMc masterchef address.
    function setCakeMc(address _cakeMc) external onlyGovernance {
        cakeMc = _cakeMc;
    }

    /// @notice Set pancake non fungible position manager.
    /// @param _cakeNfpm nfpm address.
    function setCakeNfpm(address _cakeNfpm) external onlyGovernance {
        cakeNfpm = _cakeNfpm;
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

    /// @notice Set deadline period for providing liq.
    /// @param _deadlinePeriod Deadline period.
    function setDeadlinePeriod(uint256 _deadlinePeriod) external onlyGovernance {
        deadlinePeriod = _deadlinePeriod;
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

    /// @notice Allow a module to interact with the `execute` function.
    /// @dev excodesize can be bypassed but whitelist should go through governance.
    function allowAddress(address _address) external onlyGovernance {
        if (_address == address(0)) revert AddressNull();

        /// Check if the address is a contract.
        int256 size;
        assembly {
            size := extcodesize(_address)
        }
        if (size == 0) revert NotContract();

        allowed[_address] = true;
    }

    /// @notice Disallow a module to interact with the `execute` function.
    function disallowAddress(address _address) external onlyGovernance {
        allowed[_address] = false;
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
        onlyGovernanceOrAllowed
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = to.call{value: value}(data);
        return (success, result);
    }

    /// UUPS Upgradeability.
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    receive() external payable {}
}
