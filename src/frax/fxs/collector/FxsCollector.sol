// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ISdToken} from "src/base/interfaces/ISdToken.sol";
import {IDepositor} from "src/base/interfaces/IDepositor.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

/// @title A contract that collect FXS from users and mints sdFXS at 1:1 rate when the FXS depositor will be deployed
/// @dev to be used only on fraxtal chain
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
    ISdToken public sdFxs;

    /// @notice FXS depositor
    IDepositor public fxsDepositor;

    /// @notice sdFXS gauge
    ILiquidityGauge public sdFxsGauge;

    /// @notice Address of the governance.
    address public governance;

    /// @notice Address of the future governance.
    address public futureGovernance;

    /// @notice
    mapping(address => uint256) public deposited; // user -> fxs deposited

    /// @notice Total FXS deposited by the users during the collect phase
    uint256 public totalDeposited;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Throws on auth issue
    error Auth();

    /// @notice Throws if a raw call fails
    error CallFailed();

    /// @notice Throws on phases issue
    error DifferentPhase();

    /// @notice Event emitted when Fxs are deposited by users
    /// @param user Address that deposited FXS
    /// @param amount Amount of FXS deposited
    event FxsCollected(address indexed user, uint256 amount);

    /// @notice Event emitted when Fxs are rescued by users (rescue phase)
    /// @param user Address that deposited FXS during collect phase
    /// @param recipient Adddress that receives FXS rescued
    /// @param amount Amount of FXS rescued
    event FxsRescued(address user, address recipient, uint256 amount);

    /// @notice Event emitted when the governance changes
    /// @param governance Address of new governance
    event GovernanceChanged(address governance);

    /// @notice Event emitted when sdFxs are claimed by users
    /// @param user Address of the claimer
    /// @param recipient Address that receives sdFxs or sdFxs-gauge tokens
    /// @param amount Amount claimed
    event SdFxsClaimed(address user, address recipient, uint256 amount);

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
    /// @param _recipient address that receives sdFxs or sdFxs-gauge tokens
    /// @param _deposit deposit or not sdFxs to the gauge
    function claimSdFxs(address _recipient, bool _deposit) external {
        if (currentPhase != Phase.Claim) revert DifferentPhase();

        uint256 sdFxsToClaim = deposited[msg.sender];

        if (sdFxsToClaim != 0) {
            if (_deposit) {
                ERC20(address(sdFxs)).approve(address(sdFxsGauge), sdFxsToClaim);
                sdFxsGauge.deposit(sdFxsToClaim, _recipient);
            } else {
                // transfer the whole amount deposited, in sdFxs with 1:1 rate
                ERC20(address(sdFxs)).transfer(_recipient, sdFxsToClaim);
            }

            delete deposited[msg.sender];

            emit SdFxsClaimed(msg.sender, _recipient, sdFxsToClaim);
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
            totalDeposited -= amountToRescue;

            emit FxsRescued(msg.sender, _recipient, amountToRescue);
        }
    }

    /// @notice mint sdFxs with all FXS collected during the collect phase
    /// @param _sdFxs sdFxs token
    /// @param _fxsDepositor fxs depositor
    /// @param _sdFxsGauge sdFxs gauge
    /// @param _sdFxsIncRecipient sdFxs incentives recipient
    function mintSdFxs(address _sdFxs, address _fxsDepositor, address _sdFxsGauge, address _sdFxsIncRecipient)
        external
        onlyGovernance
    {
        if (currentPhase != Phase.Collect) revert DifferentPhase();
        // set addresses
        sdFxs = ISdToken(_sdFxs);
        fxsDepositor = IDepositor(_fxsDepositor);
        sdFxsGauge = ILiquidityGauge(_sdFxsGauge);

        // deposit FXS to the depositor, receive sdFxs
        uint256 amountToDeposit = FXS.balanceOf(address(this));

        if (amountToDeposit != 0) {
            FXS.approve(address(fxsDepositor), amountToDeposit);
            fxsDepositor.deposit(amountToDeposit, true, false, address(this));

            uint256 sdFxsIncentives = ERC20(address(sdFxs)).balanceOf(address(this)) - amountToDeposit;

            if (sdFxsIncentives != 0) {
                ERC20(address(sdFxs)).transfer(_sdFxsIncRecipient, sdFxsIncentives);
            }

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
