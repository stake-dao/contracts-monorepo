// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILaPoste} from "src/common/interfaces/ILaPoste.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract APWine2SpectraConverter {
    using SafeERC20 for IERC20;

    /////////////////////////////
    /// --- Structs
    /////////////////////////////

    struct Payload {
        uint256 amount;
        address receiver;
    }

    /////////////////////////////
    /// --- VARIABLES
    /////////////////////////////

    /// @notice The sdToken use for conversion.
    address public immutable sdToken;

    /// @notice The sdToken staking contract.
    address public immutable sdTokenGauge;

    /// @notice The La Poste address.
    address public immutable laPoste;

    /// @notice The chain id to send messages.
    uint256 public immutable destinationChainId;

    /// @notice Conversion rate for old sdToken to new sdToken, 18 decimals basis
    uint256 public immutable conversionRatio;

    /////////////////////////////
    /// --- ERRORS
    /////////////////////////////

    error WrongChain();
    error NotLaPoste();
    error ZeroAddress();
    error InvalidSender();
    error NothingToRedeem();

    /////////////////////////////
    /// --- EVENTS
    /////////////////////////////

    /// @notice Emitted when conversion is initiated
    /// @param user Address sending the tokens on initial chain
    /// @param receiver Address receiving the tokens on destination chain
    /// @param amount Amount of tokens burnt and to be converted
    event ConvertedAmount(address indexed user, address indexed receiver, uint256 amount);

    /// @notice Emitted when conversion is resumed
    /// @param user Address receiving the tokens on destination chain
    /// @param receivedAmount Amount of tokens received after conversion
    /// @param convertedAmount Amount of tokens used for conversion
    event ReceivedAmount(address indexed user, uint256 receivedAmount, uint256 convertedAmount);

    /////////////////////////////
    /// --- CONSTRUCTOR
    /////////////////////////////

    /// @notice Initializes the Convertor contract with required dependencies
    /// @param _sdToken sdToken address, should be old sdToken on departure chain, and new sdToken on destination chain
    /// @param _sdTokenGauge gauge address, should be old gauge on departure chain, and new gauge on destination chain
    /// @param _laPoste Address of La Poste messaging system
    /// @param _destinationChainId Destination chain id to send message to, only used on departure chain
    /// @param _conversionRatio Conversion ratio between old sdToken and new sdToken, with 18 decimals

    constructor(
        address _sdToken,
        address _sdTokenGauge,
        address _laPoste,
        uint256 _destinationChainId,
        uint256 _conversionRatio
    ) {
        sdToken = _sdToken;
        sdTokenGauge = _sdTokenGauge;
        laPoste = _laPoste;
        destinationChainId = _destinationChainId;
        conversionRatio = _conversionRatio;

        if (block.chainid != 1) {
            IERC20(sdToken).approve(sdTokenGauge, type(uint256).max);
        }
    }

    /////////////////////////////
    /// --- MODIFIERS
    /////////////////////////////

    modifier onlyMainnet(uint256 chainId) {
        if (chainId != 1) revert WrongChain();
        _;
    }

    modifier onlyLaPoste() {
        if (msg.sender != laPoste) revert NotLaPoste();
        _;
    }

    /////////////////////////////
    /// --- PUBLIC FUNCTIONS
    /////////////////////////////

    /// @notice Initializes a conversion of old sdToken to a new sdToken, by sending a message to La Poste
    /// @param _receiver Address of the address receiving the new sdToken on destination chain
    /// @param _additionalGasLimit Additional gas limit for transaction execution on destination chain
    function initConvert(address _receiver, uint256 _additionalGasLimit) external payable onlyMainnet(block.chainid) {
        if (_receiver == address(0)) revert ZeroAddress();

        // 1. Transfer sdTokens from user to this contract
        uint256 redeemAmount = IERC20(sdToken).balanceOf(msg.sender);

        if (redeemAmount > 0) {
            IERC20(sdToken).safeTransferFrom(msg.sender, address(this), redeemAmount);
        }

        // 2. Unstake from gauge: claim rewards + withdraw
        uint256 sdTokenGaugeBalance = ILiquidityGauge(sdTokenGauge).balanceOf(msg.sender);
        if (sdTokenGaugeBalance > 0) {
            // Claim rewards to msg.sender
            ILiquidityGauge(sdTokenGauge).claim_rewards(msg.sender);

            // Transfer gauge shares from user to this contract
            IERC20(sdTokenGauge).safeTransferFrom(msg.sender, address(this), sdTokenGaugeBalance);

            // Withdraw staked tokens from gauge to this contract
            ILiquidityGauge(sdTokenGauge).withdraw(sdTokenGaugeBalance, false);

            // Add the gauge balance to the redeem amount
            redeemAmount += sdTokenGaugeBalance;
        }

        // 3. Check if there is anything to redeem
        if (redeemAmount == 0) revert NothingToRedeem();

        // 4. Burn sdTokens
        ISdToken(sdToken).burn(address(this), redeemAmount);

        // 5. Build and send message to La Poste to initiate conversion
        bytes memory payload = abi.encode(Payload({amount: redeemAmount, receiver: _receiver}));

        ILaPoste.MessageParams memory messageParams = ILaPoste.MessageParams({
            destinationChainId: destinationChainId,
            to: address(this),
            tokens: new ILaPoste.Token[](0),
            payload: payload
        });

        ILaPoste(laPoste).sendMessage{value: msg.value}(messageParams, _additionalGasLimit, _receiver);

        emit ConvertedAmount(msg.sender, _receiver, redeemAmount);
    }

    /// @notice Resolution of the conversion, should only be called by La Poste on destination chain
    /// @param (unused) Departure chain of the message
    /// @param sender Address sending the message from the departure chain, should be the same as address(this)
    /// @param payload bytes of data for parameters, should fit the Payload structure when decoded
    function receiveMessage(uint256, address sender, bytes calldata payload) external onlyLaPoste {
        if (sender != address(this)) revert InvalidSender();

        // 1. Decode payload
        Payload memory _payload = abi.decode(payload, (Payload));

        // 2. Compute amount of sdTokens and stake them for the receiver
        uint256 toSend = _payload.amount * conversionRatio / 10 ** 18;
        ILiquidityGauge(sdTokenGauge).deposit(toSend, _payload.receiver);

        emit ReceivedAmount(_payload.receiver, toSend, _payload.amount);
    }
}
