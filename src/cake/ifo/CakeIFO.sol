// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {IExecutor} from "src/base/interfaces/IExecutor.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ICakeIFOV7} from "src/base/interfaces/ICakeIFOV7.sol";
import {ICakeV3} from "src/base/interfaces/ICakeV3.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {MerkleProofLib} from "solmate/utils/MerkleProofLib.sol";
import {CakeIFOFactory} from "src/cake/ifo/CakeIFOFactory.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

contract CakeIFO {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Address of the pancake ifo contract
    ICakeIFOV7 public immutable cakeIFO;

    /// @notice Address of the sd ifo factoruy
    CakeIFOFactory public immutable ifoFactory;

    /// @notice Executor
    IExecutor public immutable executor;

    /// @notice Address of the deposit token
    ERC20 public immutable dToken;

    /// @notice Address of the offering token
    ERC20 public immutable oToken;

    /// @notice Address of the locker
    address public immutable locker;

    /// @notice First period start ts
    uint256 public immutable firstPeriodStart;

    /// @notice First period end ts
    uint256 public immutable firstPeriodEnd;

    /// @notice sdCake gauge total supply
    uint256 public sdCakeGaugeTotalSupply;

    /// @notice merkle root
    bytes32 public merkleRoot;

    /// @notice user -> pid -> amount
    mapping(address => mapping(uint8 => uint256)) public depositors;

    /// @notice pid -> oToken reward rate
    mapping(uint8 => uint256) public rewardRate;

    /// @notice pid -> dToken refund rate
    mapping(uint8 => uint256) public refundRate;

    /// @notice user -> pid -> oToken reward claimed
    mapping(address => mapping(uint8 => uint256)) public rewardClaimed;

    /// @notice user -> pid -> dToken refund claimed
    mapping(address => mapping(uint8 => uint256)) public refundClaimed;

    /// @notice pid -> total dToken deposited for each pool
    mapping(uint8 => uint256) public totalDeposits;

    /// @notice user -> total amount deposited by users
    mapping(address => uint256) public userTotalDeposits;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Throwed when a low level call failed
    error CallFailed();

    /// @notice Throwed when an user trying to deposit more than max
    error AboveMax();

    /// @notice Throwed at deploy time if the IFO ended
    error IfoEnded();

    /// @notice Throwed when the IFO not started
    error IfoNotStarted();

    /// @notice Throwed when the proof is invalid
    error InvalidProof();

    /// @notice Throwed if the merkle root has not set
    error MerkleRootNotSet();

    /// @notice Throwed if the user has not deposited any dToken
    error NoDeposit();

    /// @notice Throwed on Auth
    error OnlyFactory();

    /// @notice Throwed if it's not in first period
    error NotInFirstPeriod();

    /// @notice Throwed if it's not in the second period
    error NotInSecondPeriod();

    /// @notice Throwed when the address is not set
    error ZeroAddress();

    /// @notice Emitted when an user claim
    event Claim(address user, uint256 reward, uint256 refund);

    /// @notice Emitted when an user deposit
    event Deposit(address user, uint8 pid, uint256 amount);

    /// @notice Emitted when a pool has harvested
    event Harvest(uint8 pid, uint256 harvest, uint256 refund);

    /// @notice Emitted when a release has triggered for the vesting schedule
    event Release(bytes32 vestingScheduleId, uint256 amount);

    /// @param _ifo Address of a pancake ifo.
    /// @param _dToken Address of the deposit token.
    /// @param _oToken Address of the offering token.
    /// @param _locker Address of the cake locker.
    /// @param _executor Address of the executor.
    /// @param _ifoFactory Address of the ifo factory.
    constructor(
        address _ifo,
        address _dToken,
        address _oToken,
        address _locker,
        address _executor,
        address _ifoFactory
    ) {
        cakeIFO = ICakeIFOV7(_ifo);
        // check if ifo already started
        uint256 startTimestamp = ICakeIFOV7(cakeIFO).startTimestamp();
        uint256 endTimestamp = ICakeIFOV7(cakeIFO).endTimestamp();
        uint256 _firstPeriodStart;
        uint256 _firstPeriodEnd;
        // IFO not started yet
        if (block.timestamp < startTimestamp) {
            _firstPeriodStart = startTimestamp;
            _firstPeriodEnd = endTimestamp - startTimestamp / 2;
        } else if (block.timestamp >= startTimestamp && block.timestamp < endTimestamp) {
            // IFO started but not ended
            _firstPeriodStart = block.timestamp;
            _firstPeriodEnd = _firstPeriodStart + ((endTimestamp - block.timestamp) / 2);
        } else {
            // IFO already ended
            revert IfoEnded();
        }
        firstPeriodStart = _firstPeriodStart;
        firstPeriodEnd = _firstPeriodEnd;

        executor = IExecutor(_executor);
        dToken = ERC20(_dToken);
        oToken = ERC20(_oToken);
        locker = _locker;
        ifoFactory = CakeIFOFactory(_ifoFactory);
    }

    /// @notice Deposit dToken in the first period, only allowed by sdCake-gauge token holders
    /// @param _dAmount Amount to deposit
    /// @param _pid Pool id
    /// @param _index merkle index
    /// @param _gAmount User's gauge token amount to verify via merkle
    /// @param _merkleProof merkle proof
    function depositPoolFirstPeriod(
        uint256 _dAmount,
        uint8 _pid,
        uint256 _index,
        uint256 _gAmount,
        bytes32[] calldata _merkleProof
    ) external {
        // check if the IFO is in first period
        if (block.timestamp < firstPeriodStart || block.timestamp > firstPeriodEnd) revert NotInFirstPeriod();

        // check if the merkle root has been set
        if (merkleRoot == "") revert MerkleRootNotSet();

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(_index, msg.sender, _gAmount));
        if (!MerkleProofLib.verify(_merkleProof, merkleRoot, node)) revert InvalidProof();

        // transfer dToken from user to locker
        SafeTransferLib.safeTransferFrom(address(dToken), msg.sender, locker, _dAmount);

        // check max lp limit for the pool
        (,, uint256 lpLimit,,,, uint8 saleType) = cakeIFO.viewPoolInformation(_pid);

        // if sale is not private get the locker credit
        uint256 lockerCredit;
        if (saleType != 1) {
            lockerCredit = ICakeV3(cakeIFO.iCakeAddress()).getUserCreditWithIfoAddr(locker, address(cakeIFO));
        }
        
        // if sale is private without any lp limit, skip it
        if (lpLimit != 0 || lockerCredit != 0) {
            if (lpLimit == 0) {
                // public/basic sale
                // if lpLimit has not set, takes the lockerCredit
                lpLimit = lockerCredit;
            } else if (lpLimit != 0 && lockerCredit != 0) {
                // if lpLimit has set, takes the min
                lpLimit = lpLimit < lockerCredit ? lpLimit : lockerCredit;
            }

            uint256 dTokenDepositable = lpLimit.mulDiv(1e18, sdCakeGaugeTotalSupply).mulDiv(_gAmount, 1e18);
            if (dTokenDepositable < _dAmount + userTotalDeposits[msg.sender]) revert AboveMax();
        }

        _deposit(_dAmount, _pid);
    }

    /// @notice Deposit dToken in the second period (open to anyone).
    /// @param _dAmount Amount of dToken to deposit.
    /// @param _pid Pool id.
    function depositPoolSecondPeriod(uint256 _dAmount, uint8 _pid) external {
        // check if the IFO is in second period
        if (block.timestamp < firstPeriodEnd || block.timestamp > ICakeIFOV7(cakeIFO).endTimestamp()) {
            revert NotInSecondPeriod();
        }

        // transfer dToken here to charge fees
        SafeTransferLib.safeTransferFrom(address(dToken), msg.sender, address(this), _dAmount);

        // charge fees on the dToken
        _dAmount -= _chargeProtocolFees(_dAmount);

        // transfer dToken remained to locker
        SafeTransferLib.safeTransfer(address(dToken), locker, _dAmount);

        _deposit(_dAmount, _pid);
    }

    /// @notice Internal function to deposit the dToken on the pancake IFO on behalf of the locker.
    /// @param _dAmount Amount to deposit.
    /// @param _pid Pool id.
    function _deposit(uint256 _dAmount, uint8 _pid) internal {
        bytes memory approveData = abi.encodeWithSignature("approve(address,uint256)", address(cakeIFO), _dAmount);
        (bool success,) = ifoFactory.callExecuteToLocker(address(dToken), approveData);
        if (!success) revert CallFailed();

        // deposit dToken to cakeIFO
        bytes memory depositData = abi.encodeWithSignature("depositPool(uint256,uint8)", _dAmount, _pid);
        (success,) = ifoFactory.callExecuteToLocker(address(cakeIFO), depositData);
        if (!success) revert CallFailed();

        depositors[msg.sender][_pid] += _dAmount;
        userTotalDeposits[msg.sender] += _dAmount;
        totalDeposits[_pid] += _dAmount;

        emit Deposit(msg.sender, _pid, _dAmount);
    }

    /// @notice Internal function to charge protocol fees.
    /// @param _amount Amount to charge fees on
    /// @return fee Amount charged earned by protocol.
    function _chargeProtocolFees(uint256 _amount) internal returns (uint256 fee) {
        uint256 protocolFeesPercent = ifoFactory.protocolFeesPercent();
        if (_amount == 0 || protocolFeesPercent == 0) return 0;

        address feeReceiver = ifoFactory.feeReceiver();
        if (feeReceiver == address(0)) revert ZeroAddress();

        fee = _amount.mulDiv(protocolFeesPercent, ifoFactory.DENOMINATOR());

        SafeTransferLib.safeTransfer(address(dToken), ifoFactory.feeReceiver(), fee);
    }

    /// @notice Harvest a pool at the end of the IFO (callable only once per pid).
    /// @param _pid Pool id.
    function harvestPool(uint8 _pid) external {
        uint256 snapshotDToken = dToken.balanceOf(locker);
        uint256 snapshotOToken = oToken.balanceOf(locker);

        bytes memory harvestData = abi.encodeWithSignature("harvestPool(uint8)", _pid);
        (bool success,) = ifoFactory.callExecuteToLocker(address(cakeIFO), harvestData);
        if (!success) revert CallFailed();

        uint256 oTokenHarvested = oToken.balanceOf(locker) - snapshotOToken;

        if (oTokenHarvested != 0) {
            // transfer token here
            bytes memory transferData =
                abi.encodeWithSignature("transfer(address,uint256)", address(this), oTokenHarvested);
            (success,) = ifoFactory.callExecuteToLocker(address(oToken), transferData);
            if (!success) revert CallFailed();
            // increase reward rate
            rewardRate[_pid] += oTokenHarvested.mulDiv(1e18, totalDeposits[_pid]);
        }

        uint256 dTokenRefunded = dToken.balanceOf(locker) - snapshotDToken;

        if (dTokenRefunded != 0) {
            // transfer token here
            bytes memory transferData =
                abi.encodeWithSignature("transfer(address,uint256)", address(this), dTokenRefunded);
            (success,) = ifoFactory.callExecuteToLocker(address(dToken), transferData);
            if (!success) revert CallFailed();
            // increase refund rate
            refundRate[_pid] += dTokenRefunded.mulDiv(1e18, totalDeposits[_pid]);
        }

        emit Harvest(_pid, oTokenHarvested, dTokenRefunded);
    }

    /// @notice Release reward in vesting.
    /// @param _pid Pool id.
    function release(uint8 _pid) external {
        _release(_pid);
    }

    /// @notice Internal release function
    /// @param _pid Pool id.
    function _release(uint8 _pid) internal {
        // fetch vestingSchedule
        bytes32 vestingScheduleId = cakeIFO.computeVestingScheduleIdForAddressAndPid(locker, _pid);

        uint256 snapshotOToken = oToken.balanceOf(locker);

        bytes memory releaseData = abi.encodeWithSignature("release(bytes32)", vestingScheduleId);
        (bool success,) = ifoFactory.callExecuteToLocker(address(cakeIFO), releaseData);
        if (!success) revert CallFailed();

        uint256 oTokenReleased = oToken.balanceOf(locker) - snapshotOToken;

        if (oTokenReleased != 0) {
            // transfer token here
            bytes memory transferData =
                abi.encodeWithSignature("transfer(address,uint256)", address(this), oTokenReleased);
            (success,) = ifoFactory.callExecuteToLocker(address(oToken), transferData);
            if (!success) revert CallFailed();
            rewardRate[_pid] += oTokenReleased.mulDiv(1e18, totalDeposits[_pid]);
        }

        emit Release(vestingScheduleId, oTokenReleased);
    }

    /// @notice Claim reward by users.
    /// @param _pid Pool id.
    /// @param _releaseVesting Release or not the vesting reward.
    function claim(uint8 _pid, bool _releaseVesting) external {
        uint256 deposited = depositors[msg.sender][_pid];
        if (deposited == 0) revert NoDeposit();

        // release vesting rewards
        if (_releaseVesting) {
            _release(_pid);
        }

        uint256 rewardToClaim =
            deposited.mulDiv(rewardRate[_pid], 1e18) - rewardClaimed[msg.sender][_pid];
        uint256 refundToClaim =
            deposited.mulDiv(refundRate[_pid], 1e18) - refundClaimed[msg.sender][_pid];

        if (rewardToClaim != 0) {
            SafeTransferLib.safeTransfer(address(oToken), msg.sender, rewardToClaim);
            rewardClaimed[msg.sender][_pid] += rewardToClaim;
        }

        if (refundToClaim != 0) {
            SafeTransferLib.safeTransfer(address(dToken), msg.sender, refundToClaim);
            refundClaimed[msg.sender][_pid] += refundToClaim;
        }

        emit Claim(msg.sender, rewardToClaim, refundToClaim);
    }

    /// @notice Set the merkle root to verify the user's gauge balance.
    /// @param _merkleRoot Root of the merkle.
    /// @param _sdCakeGaugeTotalSupply Total supply of the sdCake gauge.
    function setMerkleRoot(bytes32 _merkleRoot, uint256 _sdCakeGaugeTotalSupply) external {
        if (msg.sender != address(ifoFactory)) revert OnlyFactory();
        merkleRoot = _merkleRoot;
        sdCakeGaugeTotalSupply = _sdCakeGaugeTotalSupply;
    }
}
