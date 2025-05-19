// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {IDepositor} from "src/common/interfaces/IDepositor.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";

/// @title A contract that collect Token from users and mints sdToken at 1:1 rate, later on, when the depositor will be deployed
/// @dev To be used only on the Fraxtal chain (ad-hoc contructor to delegate the Fraxtal network's rewards).
/// @author StakeDAO
abstract contract Collector is ERC20 {
    enum Phase {
        Collect, // 0
        Claim, // 1
        Rescue // 2

    }

    /// @notice Current phase
    Phase public currentPhase;

    /// @notice Token to deposit
    ERC20 public immutable token;

    /// @notice sdToken token
    ISdToken public sdToken;

    /// @notice Token BaseDepositor
    IDepositor public depositor;

    /// @notice sdToken gauge
    ILiquidityGauge public sdTokenGauge;

    /// @notice collector gauge
    ILiquidityGauge public collectorGauge;

    /// @notice Address of the governance.
    address public governance;

    /// @notice Address of the future governance.
    address public futureGovernance;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Throws on auth issue
    error Auth();

    /// @notice Throws if a raw call fails
    error CallFailed();

    /// @notice Throws on phases issue
    error DifferentPhase();

    /// @notice Throws if zero address
    error ZeroAddress();

    /// @notice Event emitted every time token are deposited by users
    /// @param user Address that deposited token
    /// @param recipient Address deposited for
    /// @param amount Amount of token deposited
    event Deposited(address indexed user, address indexed recipient, uint256 amount);

    /// @notice Event emitted when token are rescued by users (rescue phase)
    /// @param user Address that deposited token during collect phase
    /// @param recipient Adddress that receives token rescued
    /// @param amount Amount of token rescued
    event Rescued(address user, address recipient, uint256 amount);

    /// @notice Event emitted when the governance changes
    /// @param governance Address of new governance
    event GovernanceChanged(address governance);

    /// @notice Event emitted when sdToken are claimed by users
    /// @param user Address of the claimer
    /// @param recipient Address that receives sdToken or sdToken-gauge tokens
    /// @param amount Amount claimed
    /// @param deposit Deposit or not sdToken into the gauge
    event SdTokenClaimed(address user, address recipient, uint256 amount, bool deposit);

    modifier onlyGovernance() {
        if (msg.sender != governance) revert Auth();
        _;
    }

    /// @notice Constructor
    /// @param _governance Address of the governance
    /// @param _token Token to deposit
    constructor(address _governance, address _token) {
        governance = _governance;
        token = ERC20(_token);
    }

    function name() public view virtual override returns (string memory) {
        return "Collector";
    }

    function symbol() public view virtual override returns (string memory) {
        return "C";
    }

    /// @notice Deposit Token into the collector
    /// @param _amount Amount of Token to deposit
    /// @param _recipient Address to deposit for
    function deposit(uint256 _amount, address _recipient) external {
        // check current phase
        if (currentPhase != Phase.Collect) revert DifferentPhase();
        // check if the collector gauge has been set
        if (address(collectorGauge) == address(0)) revert ZeroAddress();

        // collect Token from user
        token.transferFrom(msg.sender, address(this), _amount);

        // mint and stake for the user
        _mint(address(this), _amount);
        ERC20(address(this)).approve(address(collectorGauge), _amount);
        collectorGauge.deposit(_amount, _recipient);

        emit Deposited(msg.sender, _recipient, _amount);
    }

    /// @notice Claim sdToken
    /// @param _recipient Address that receives sdToken or sdToken-gauge tokens
    /// @param _deposit Deposit or not sdToken to the gauge
    function claimSdToken(address _recipient, bool _deposit) external {
        // check current phase
        if (currentPhase != Phase.Claim) revert DifferentPhase();
        // check if the collector gauge has been set
        if (address(collectorGauge) == address(0)) revert ZeroAddress();

        uint256 sdTokenToClaim = collectorGauge.balanceOf(msg.sender);

        if (sdTokenToClaim != 0) {
            if (_deposit) {
                ERC20(address(sdToken)).approve(address(sdTokenGauge), sdTokenToClaim);
                sdTokenGauge.deposit(sdTokenToClaim, _recipient);
            } else {
                // transfer the whole amount deposited, in sdToken with 1:1 rate
                ERC20(address(sdToken)).transfer(_recipient, sdTokenToClaim);
            }

            // unstake and burn
            collectorGauge.withdraw(sdTokenToClaim, msg.sender, false);
            _burn(address(this), sdTokenToClaim);

            emit SdTokenClaimed(msg.sender, _recipient, sdTokenToClaim, _deposit);
        }
    }

    /// @notice Rescue Token deposited during the collect phase
    /// @param _recipient Token receiver
    function rescueToken(address _recipient) external {
        // check current phase
        if (currentPhase != Phase.Rescue) revert DifferentPhase();
        // check if the collector gauge has been set
        if (address(collectorGauge) == address(0)) revert ZeroAddress();

        uint256 amountToRescue = collectorGauge.balanceOf(msg.sender);

        if (amountToRescue != 0) {
            // give back Token to the user
            token.transfer(_recipient, amountToRescue);

            // unstake and burn
            collectorGauge.withdraw(amountToRescue, msg.sender, false);
            _burn(address(this), amountToRescue);

            emit Rescued(msg.sender, _recipient, amountToRescue);
        }
    }

    /// @notice Mint sdToken with all Token collected during the collect phase
    /// @param _sdToken sdToken token
    /// @param _depositor Token depositor
    /// @param _sdTokenGauge sdToken gauge
    /// @param _sdTokenIncRecipient sdToken incentives recipient
    function mintSdToken(address _sdToken, address _depositor, address _sdTokenGauge, address _sdTokenIncRecipient)
        external
        onlyGovernance
    {
        if (currentPhase != Phase.Collect) revert DifferentPhase();
        // set addresses
        sdToken = ISdToken(_sdToken);
        depositor = IDepositor(_depositor);
        sdTokenGauge = ILiquidityGauge(_sdTokenGauge);

        // deposit Token to the depositor, receive sdToken
        uint256 amountToDeposit = token.balanceOf(address(this));

        if (amountToDeposit != 0) {
            token.approve(address(depositor), amountToDeposit);
            // deposit the whole amount to the depositor, locking but without staking
            depositor.deposit(amountToDeposit, true, false, address(this));

            // check if the deposit() collected extra incentives too
            uint256 sdTokenIncentives = ERC20(address(sdToken)).balanceOf(address(this)) - amountToDeposit;

            // transfer incentives minted, if any, to the recipient
            if (sdTokenIncentives != 0) {
                ERC20(address(sdToken)).transfer(_sdTokenIncRecipient, sdTokenIncentives);
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

    /// @notice Set the collector gauge
    /// @param _collectorGauge Address of the collectorGauge
    function setCollectorGauge(address _collectorGauge) external onlyGovernance {
        collectorGauge = ILiquidityGauge(_collectorGauge);
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
