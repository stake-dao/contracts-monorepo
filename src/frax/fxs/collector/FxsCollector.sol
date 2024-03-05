// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ISdToken} from "src/base/interfaces/ISdToken.sol";
import {IDepositor} from "src/base/interfaces/IDepositor.sol";

/// @title A contract that collect FXS from users and mints sdFXS at 1:1 rate when the FXS depositor will be deployed
/// @dev to be used only on fraxtal chain
/// @author StakeDAO
contract FxsCollector {
    enum Phase {
        Collect, // 0
        Mint, // 1
        Claim, // 2
        Rescue // 3

    }

    Phase public currentPhase;

    ERC20 public constant FXS = ERC20(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);

    ISdToken public sdFxs;

    IDepositor public fxsDepositor;

    address public governance;

    address public futureGovernance;

    mapping(address => uint256) public deposited; // user -> fxs deposited

    uint256 public totalDeposited;

    // Errors and Events

    error Auth();

    error CallFailed();

    error DifferentPhase();

    event FxsCollected(address indexed user, uint256 amount);

    event FxsRescued(address user, address recipient, uint256 amount);

    event GovernanceChanged(address governance);

    event SdFxsClaimed(address user, address _recipient, uint256 amount);

    modifier onlyGovernance() {
        if (msg.sender != governance) revert Auth();
        _;
    }

    constructor(address _governance, address _delegationRegistry, address _initialDelegate) {
        (bool success,) =
            _delegationRegistry.call(abi.encodeWithSignature("setDelegationForSelf(address)", _initialDelegate));
        if (!success) revert CallFailed();
        (success,) = _delegationRegistry.call(abi.encodeWithSignature("disableSelfManagingDelegations()"));
        if (!success) revert CallFailed();
        governance = _governance;
    }

    /// @notice Collect FXS from users
    /// @param _amount amount of FXS to deposit
    function collectFXS(uint256 _amount) external {
        // check current phase
        if (currentPhase != Phase.Collect) revert DifferentPhase();

        // collect fxs from user
        FXS.transferFrom(msg.sender, address(this), _amount);

        // increase the amount deposited
        deposited[msg.sender] += _amount;
        totalDeposited += _amount;

        emit FxsCollected(msg.sender, _amount);
    }

    /// @notice Claim sdFxs
    function claimSdFxs(address _recipient) external {
        if (currentPhase != Phase.Claim) revert DifferentPhase();

        uint256 sdFxsToMint = deposited[msg.sender];

        if (sdFxsToMint != 0) {
            // transfer the whole amount deposited, in sdFxs with 1:1 rate
            ERC20(address(sdFxs)).transfer(_recipient, sdFxsToMint);

            delete deposited[msg.sender];
        }

        emit SdFxsClaimed(msg.sender, _recipient, sdFxsToMint);
    }

    /// @notice Rescue FXS deposited during the collect phase
    /// @param _recipient FXS receiver
    function rescueFXS(address _recipient) external {
        // check current phase
        if (currentPhase != Phase.Rescue) revert DifferentPhase();

        uint256 amountToRescue = deposited[msg.sender];

        if (amountToRescue != 0) {
            // give back FXS to the user
            FXS.transfer(_recipient, amountToRescue);

            delete deposited[msg.sender];
            totalDeposited -= amountToRescue;

            emit FxsRescued(msg.sender, _recipient, amountToRescue);
        }
    }

    /// @notice mint sdFxs with all FXS collected during the collect phase
    /// @param _sdFxsIncRecipient sdFxs incentives recipient
    function mintSdFxs(address _sdFxsIncRecipient) external onlyGovernance {
        if (currentPhase != Phase.Mint) revert DifferentPhase();
        // deposit FXS to the depositor, receive sdFxs
        uint256 amountToDeposit = FXS.balanceOf(address(this));

        if (amountToDeposit != 0) {
            FXS.approve(address(fxsDepositor), amountToDeposit);
            fxsDepositor.deposit(amountToDeposit, true, false, address(this));
        }

        uint256 sdFxsIncentives = ERC20(address(sdFxs)).balanceOf(address(this)) - amountToDeposit;

        if (sdFxsIncentives != 0) {
            ERC20(address(sdFxs)).transfer(_sdFxsIncRecipient, sdFxsIncentives);
        }

        currentPhase = Phase.Claim;
    }

    /// @notice Trigger the Mint phase
    /// @param _sdFxs sdFxs address
    /// @param _fxsDepositor fxsDepositor
    function triggerMintPhase(address _sdFxs, address _fxsDepositor) external onlyGovernance {
        sdFxs = ISdToken(_sdFxs);
        fxsDepositor = IDepositor(_fxsDepositor);

        currentPhase = Phase.Mint;
    }

    /// @notice Toggle rescue mode
    function togglePhase(Phase _phase) external onlyGovernance {
        currentPhase = _phase;
    }

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert Auth();

        governance = msg.sender;
        futureGovernance = address(0);
        emit GovernanceChanged(msg.sender);
    }
}
