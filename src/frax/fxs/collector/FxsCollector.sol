// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ISdToken} from "src/base/interfaces/ISdToken.sol";
import {IDepositor} from "src/base/interfaces/IDepositor.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

/// @title A contract that collect FXS from users and mints sdFXS at 1:1 rate, later on, when the FXS depositor will be deployed
/// @dev To be used only on the Fraxtal chain (ad-hoc contructor to delegate the Fraxtal network's rewards).
/// @author StakeDAO
contract FxsCollector {
    enum Phase {
        Collect, // 0
        Claim, // 1
        Rescue // 2

    }

    /// @notice Current phase
    Phase public currentPhase;

    /// @notice Fraxtal FXS token
    ERC20 public constant FXS = ERC20(0xFc00000000000000000000000000000000000002);

    /// @notice sdFXS token
    ISdToken public sdFXS;

    /// @notice FXS depositor
    IDepositor public fxsDepositor;

    /// @notice sdFXS gauge
    ILiquidityGauge public sdFXSGauge;

    /// @notice Address of the governance.
    address public governance;

    /// @notice Address of the future governance.
    address public futureGovernance;

    /// @notice
    mapping(address => uint256) public deposited; // user -> FXS deposited

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Throws on auth issue
    error Auth();

    /// @notice Throws if a raw call fails
    error CallFailed();

    /// @notice Throws on phases issue
    error DifferentPhase();

    /// @notice Event emitted when FXS are deposited by users
    /// @param user Address that deposited FXS
    /// @param recipient Address deposited for
    /// @param amount Amount of FXS deposited
    event FXSDeposited(address indexed user, address indexed recipient, uint256 amount);

    /// @notice Event emitted when FXS are rescued by users (rescue phase)
    /// @param user Address that deposited FXS during collect phase
    /// @param recipient Adddress that receives FXS rescued
    /// @param amount Amount of FXS rescued
    event FXSRescued(address user, address recipient, uint256 amount);

    /// @notice Event emitted when the governance changes
    /// @param governance Address of new governance
    event GovernanceChanged(address governance);

    /// @notice Event emitted when sdFXS are claimed by users
    /// @param user Address of the claimer
    /// @param recipient Address that receives sdFXS or sdFXS-gauge tokens
    /// @param amount Amount claimed
    /// @param deposit Deposit or not sdFXS into the gauge
    event SdFXSClaimed(address user, address recipient, uint256 amount, bool deposit);

    modifier onlyGovernance() {
        if (msg.sender != governance) revert Auth();
        _;
    }

    /// @notice Constructor
    /// @param _governance Address of the governance
    /// @param _delegationRegistry Address of the Fraxtal's Frax Delegation registry used to delegate epoch reward
    /// @param _initialDelegate Address of the delegate reward contract that receives it at every epoch on fraxtal
    constructor(address _governance, address _delegationRegistry, address _initialDelegate) {
        (bool success,) =
            _delegationRegistry.call(abi.encodeWithSignature("setDelegationForSelf(address)", _initialDelegate));
        if (!success) revert CallFailed();
        (success,) = _delegationRegistry.call(abi.encodeWithSignature("disableSelfManagingDelegations()"));
        if (!success) revert CallFailed();
        governance = _governance;
    }

    /// @notice Deposit FXS into the collector
    /// @param _amount Amount of FXS to deposit
    /// @param _recipient Address to deposit for
    function depositFXS(uint256 _amount, address _recipient) external {
        // check current phase
        if (currentPhase != Phase.Collect) revert DifferentPhase();

        // collect FXS from user
        FXS.transferFrom(msg.sender, address(this), _amount);

        // increase the amount deposited
        deposited[_recipient] += _amount;

        emit FXSDeposited(msg.sender, _recipient, _amount);
    }

    /// @notice Claim sdFXS
    /// @param _recipient Address that receives sdFXS or sdFXS-gauge tokens
    /// @param _deposit Deposit or not sdFXS to the gauge
    function claimSdFXS(address _recipient, bool _deposit) external {
        if (currentPhase != Phase.Claim) revert DifferentPhase();

        uint256 sdFXSToClaim = deposited[msg.sender];

        if (sdFXSToClaim != 0) {
            if (_deposit) {
                ERC20(address(sdFXS)).approve(address(sdFXSGauge), sdFXSToClaim);
                sdFXSGauge.deposit(sdFXSToClaim, _recipient);
            } else {
                // transfer the whole amount deposited, in sdFXS with 1:1 rate
                ERC20(address(sdFXS)).transfer(_recipient, sdFXSToClaim);
            }

            delete deposited[msg.sender];

            emit SdFXSClaimed(msg.sender, _recipient, sdFXSToClaim, _deposit);
        }
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

            emit FXSRescued(msg.sender, _recipient, amountToRescue);
        }
    }

    /// @notice Mint sdFXS with all FXS collected during the collect phase
    /// @param _sdFXS sdFXS token
    /// @param _fxsDepositor FXS depositor
    /// @param _sdFXSGauge sdFXS gauge
    /// @param _sdFXSIncRecipient sdFXS incentives recipient
    function mintSdFXS(address _sdFXS, address _fxsDepositor, address _sdFXSGauge, address _sdFXSIncRecipient)
        external
        onlyGovernance
    {
        if (currentPhase != Phase.Collect) revert DifferentPhase();
        // set addresses
        sdFXS = ISdToken(_sdFXS);
        fxsDepositor = IDepositor(_fxsDepositor);
        sdFXSGauge = ILiquidityGauge(_sdFXSGauge);

        // deposit FXS to the depositor, receive sdFXS
        uint256 amountToDeposit = FXS.balanceOf(address(this));

        if (amountToDeposit != 0) {
            FXS.approve(address(fxsDepositor), amountToDeposit);
            // deposit the whole amount to the fxsDepositor, locking but without staking
            fxsDepositor.deposit(amountToDeposit, true, false, address(this));

            // check if the deposit() collected extra incentives too
            uint256 sdFXSIncentives = ERC20(address(sdFXS)).balanceOf(address(this)) - amountToDeposit;

            // transfer incentives minted, if any, to the recipient
            if (sdFXSIncentives != 0) {
                ERC20(address(sdFXS)).transfer(_sdFXSIncRecipient, sdFXSIncentives);
            }

            // enable claim phase
            currentPhase = Phase.Claim;
        }
    }

    /// @notice Toggle rescue mode (it can be done only during Collect phase)
    function toggleRescuePhase() external onlyGovernance {
        if (currentPhase != Phase.Collect) revert DifferentPhase();
        currentPhase = Phase.Rescue;
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
