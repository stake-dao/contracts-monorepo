// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {CakeIFO} from "src/bnb/cake/ifo/CakeIFO.sol";
import {IExecutor} from "src/common/interfaces/IExecutor.sol";
import {ICakeIFOV8} from "src/common/interfaces/ICakeIFOV8.sol";

contract CakeIFOFactory {
    /// @notice Address of the executor
    IExecutor public immutable executor;

    /// @notice Address of the locker
    address public immutable locker;

    /// @notice Address of the governance
    address public governance;

    /// @notice Address of the future governance
    address public futureGovernance;

    /// @notice Address of the fee receiver
    address public feeReceiver;

    /// @notice Protocol fees percent (10000 = 100%)
    uint256 public protocolFeesPercent;

    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Take trace of allowed address
    mapping(address => bool) public allowed;

    /// @notice Take trace of ifo created
    mapping(address => address) public ifos; // sd ifo -> cake ifo

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Throwed if an address is already allowed
    error AlreadyAllowed();

    /// @notice Throwed on Auth issues
    error Auth();

    /// @notice Throwed when the fees to set it too high (> 10_000)
    error FeeTooHigh();

    /// @notice Throwed when trying to create an IFO already created
    error IfoAlreadyCreated();

    /// @notice Throwed on allowed Auth issues
    error NotAllowed();

    /// @notice Emitted when an address is allowed to set the merkle
    event Allowed(address _addr);

    /// @notice Emitted when the governance changes
    event GovernanceChanged(address _governance);

    /// @notice Emitted when an IFO is created
    event IfoCreated(address pancakeIFO, address _sdIFO);

    /// @notice Emitted when an address is disallowed to set the merkle
    event Disallowed(address _addr);

    /// @notice only governance
    modifier onlyGovernance() {
        if (msg.sender != governance) revert Auth();
        _;
    }

    /// @notice only governance or allowed
    modifier onlyGovernanceOrAllowed() {
        if (!allowed[msg.sender] && msg.sender != governance) revert NotAllowed();
        _;
    }

    /// @param _locker Address of the Cake locker.
    /// @param _executor Address of the executor.
    /// @param _governance Address of the governance.
    constructor(address _locker, address _executor, address _governance, address _feeReceiver) {
        locker = _locker;
        executor = IExecutor(_executor);
        governance = _governance;
        feeReceiver = _feeReceiver;
    }

    /// @notice Create a sd IFO.
    /// @param _cakeIFO Address of the pancake IFO contract.
    function createIFO(address _cakeIFO) external onlyGovernance {
        if (ifos[_cakeIFO] != address(0)) revert IfoAlreadyCreated();
        address dToken = ICakeIFOV8(_cakeIFO).addresses(0);
        address oToken = ICakeIFOV8(_cakeIFO).addresses(1);
        ifos[_cakeIFO] = address(new CakeIFO(_cakeIFO, dToken, oToken, locker, address(executor), address(this)));
        allowed[ifos[_cakeIFO]] = true;

        emit IfoCreated(_cakeIFO, ifos[_cakeIFO]);
    }

    /// @notice Call the execute function defined in the Cake locker, through the executor.
    /// @param _addr Address to interact in the execute.
    /// @param _data Call data.
    function callExecuteToLocker(address _addr, bytes memory _data)
        external
        onlyGovernanceOrAllowed
        returns (bool success, bytes memory result)
    {
        (success, result) = executor.callExecuteTo(locker, _addr, 0, _data);
    }

    /// @notice Set merkle root and sdCake gauge total supply at snapshot time.
    /// @param _ifo Address of the pancake ifo.
    /// @param _merkleRoot root of the merkle.
    /// @param _sdCakeGaugeTotalSupply sdCake gauge total supply.
    function setMerkleRoot(address _ifo, bytes32 _merkleRoot, uint256 _sdCakeGaugeTotalSupply)
        external
        onlyGovernanceOrAllowed
    {
        CakeIFO(_ifo).setMerkleRoot(_merkleRoot, _sdCakeGaugeTotalSupply);
    }

    /// @notice Update protocol fees.
    /// @param _protocolFee New protocol fee.
    function updateProtocolFee(uint256 _protocolFee) external onlyGovernance {
        if (_protocolFee > DENOMINATOR) revert FeeTooHigh();
        protocolFeesPercent = _protocolFee;
    }

    /// @notice Set fee receiver common for all pids
    /// @param _feeReceiver Address of the fee receiver
    function setFeeReceiver(address _feeReceiver) external onlyGovernance {
        feeReceiver = _feeReceiver;
    }

    /// @notice Allow an address to set the merkle.
    /// @param _addr Address to allow.
    function allowAddress(address _addr) external onlyGovernance {
        if (allowed[_addr]) revert AlreadyAllowed();
        allowed[_addr] = true;

        emit Allowed(_addr);
    }

    /// @notice Disallow an address to set the merkle.
    /// @param _addr Address to disallow.
    function disallowAddress(address _addr) external onlyGovernance {
        if (!allowed[_addr]) revert NotAllowed();
        allowed[_addr] = false;

        emit Disallowed(_addr);
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
