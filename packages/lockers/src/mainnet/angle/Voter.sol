// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {IExecutor} from "src/common/interfaces/IExecutor.sol";

contract AngleVoterV5 {
    /// @notice Address of the angle locker
    address public constant ANGLE_LOCKER = 0xD13F8C25CceD32cdfA79EB5eD654Ce3e484dCAF5;

    /// @notice Address of the angle gauge controller
    address public constant ANGLE_GC = 0x9aD7e7b0877582E14c17702EecF49018DD6f2367;

    /// @notice Address of the angle governor
    address public constant ANGLE_GOVERNOR = 0x748bA9Cd5a5DDba5ABA70a4aC861b2413dCa4436;

    /// @notice Address of the angle strategy
    address public angleStrategy = 0x22635427C72e8b0028FeAE1B5e1957508d9D7CAF;

    /// @notice Address of the governance
    address public governance = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    /// @notice Address of the future governance
    address public futureGovernance;

    /// @notice Error emitted when a call fails
    error CallFailed();

    /// @notice Error emitted when the arrays have different length
    error DifferentLength();

    /// @notice Event emitted when the future governance accept it
    event GovernanceChanged(address governance);

    /// @notice Error emitted on auth
    error NotAllowed();

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotAllowed();
        _;
    }

    /// @notice cast vote for angle proposal (cast 100% of vote for one choice)
    /// @param _proposalId angle proposal id
    /// @param _support (0 -> against, 1 -> for, 2 -> abstain)
    function castVote(uint256 _proposalId, uint8 _support) external onlyGovernance returns (uint256 _weight) {
        bytes memory castVoteData = abi.encodeWithSignature("castVote(uint256,uint8)", _proposalId, _support);
        (,,, _weight) = abi.decode(_executeToGovernor(castVoteData), (uint256, uint256, uint256, uint256));
    }

    /// @notice cast vote for angle proposal with reason (cast 100% of vote for one choice)
    /// @param _proposalId angle proposal id
    /// @param _support support for (0 -> against, 1 -> for, 2 -> abstain)
    /// @param _reason reason string
    function castVoteWithReason(uint256 _proposalId, uint8 _support, string calldata _reason)
        external
        onlyGovernance
        returns (uint256 _weight)
    {
        bytes memory castVoteData =
            abi.encodeWithSignature("castVoteWithReason(uint256,uint8,string)", _proposalId, _support, _reason);
        (,,, _weight) = abi.decode(_executeToGovernor(castVoteData), (uint256, uint256, uint256, uint256));
    }

    /// @notice cast vote for angle proposal with reason and params
    /// @param _proposalId angle proposal id
    /// @param _support support for (skipped for params)
    /// @param _reason reason string
    /// @param _params param
    function castVoteWithReasonAndParams(
        uint256 _proposalId,
        uint8 _support,
        string calldata _reason,
        bytes memory _params
    ) external onlyGovernance returns (uint256 _weight) {
        bytes memory castVoteData = abi.encodeWithSignature(
            "castVoteWithReasonAndParams(uint256,uint8,string,bytes)", _proposalId, _support, _reason, _params
        );
        (,,, _weight) = abi.decode(_executeToGovernor(castVoteData), (uint256, uint256, uint256, uint256));
    }

    /// @notice cast vote for angle proposal with reason and params (encoded within the function)
    /// @param _proposalId Angle proposal id
    /// @param _support support for (skipped for params)
    /// @param _reason reason string
    /// @param _againstVotes against votes
    /// @param _forVotes for votes
    /// @param _abstainVotes abstain votes
    function castVoteWithReasonAndParams(
        uint256 _proposalId,
        uint8 _support,
        string calldata _reason,
        uint128 _againstVotes,
        uint128 _forVotes,
        uint128 _abstainVotes
    ) external onlyGovernance returns (uint256 _weight) {
        bytes memory params = abi.encodePacked(_againstVotes, _forVotes, _abstainVotes);
        bytes memory castVoteData = abi.encodeWithSignature(
            "castVoteWithReasonAndParams(uint256,uint8,string,bytes)", _proposalId, _support, _reason, params
        );
        (,,, _weight) = abi.decode(_executeToGovernor(castVoteData), (uint256, uint256, uint256, uint256));
    }

    /// @notice propose a new angle governance proposal
    /// @param _targets addresses of the target contracts to execute them
    /// @param _values values
    /// @param _calldatas calldatas
    /// @param _description proposal description
    function propose(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) external onlyGovernance returns (uint256 _proposalId) {
        bytes memory proposalData = abi.encodeWithSignature(
            "propose(address[],uint256[],bytes[],string)", _targets, _values, _calldatas, _description
        );
        (,,, _proposalId) = abi.decode(_executeToGovernor(proposalData), (uint256, uint256, uint256, uint256));
    }

    /// @notice internal function to execute the cast vote call based on the _castVoteData
    /// @param _castVoteData cast vote function data
    function _executeToGovernor(bytes memory _castVoteData) internal returns (bytes memory) {
        (bool success, bytes memory _result) = IExecutor(angleStrategy).execute(
            ANGLE_LOCKER, 0, abi.encodeWithSignature("execute(address,uint256,bytes)", ANGLE_GOVERNOR, 0, _castVoteData)
        );
        if (!success) revert CallFailed();
        return _result;
    }

    /// @notice vote for angle gauges
    /// @param _gauges gauges to vote for
    /// @param _weights vote weight for each gauge
    function voteGauges(address[] calldata _gauges, uint256[] calldata _weights) external onlyGovernance {
        if (_gauges.length != _weights.length) revert DifferentLength();
        uint256 length = _gauges.length;
        for (uint256 i; i < length;) {
            bytes memory voteData =
                abi.encodeWithSignature("vote_for_gauge_weights(address,uint256)", _gauges[i], _weights[i]);
            (bool success,) = IExecutor(angleStrategy).execute(
                ANGLE_LOCKER, 0, abi.encodeWithSignature("execute(address,uint256,bytes)", ANGLE_GC, 0, voteData)
            );
            if (!success) revert CallFailed();
            unchecked {
                ++i;
            }
        }
    }

    /// @notice execute a function
    /// @param _to Address to sent the value to
    /// @param _value Value to be sent
    /// @param _data Call function data
    function execute(address _to, uint256 _value, bytes calldata _data)
        external
        onlyGovernance
        returns (bool success, bytes memory result)
    {
        (success, result) = _to.call{value: _value}(_data);
        if (!success) revert CallFailed();
    }

    /// @notice execute a function and transfer funds to the given address
    /// @param _to Address to sent the value to
    /// @param _value Value to be sent
    /// @param _data Call function data
    /// @param _token address of the token that we will transfer
    /// @param _recipient address of the recipient that will get the tokens
    function executeAndTransfer(address _to, uint256 _value, bytes calldata _data, address _token, address _recipient)
        external
        onlyGovernance
        returns (bool success)
    {
        (success,) = _to.call{value: _value}(_data);
        if (!success) revert CallFailed();

        uint256 tokenBalance = ERC20(_token).balanceOf(ANGLE_LOCKER);
        bytes memory transferData = abi.encodeWithSignature("transfer(address,uint256)", _recipient, tokenBalance);
        bytes memory executeData = abi.encodeWithSignature("execute(address,uint256,bytes)", _token, 0, transferData);
        (success,) = IExecutor(angleStrategy).execute(ANGLE_LOCKER, 0, executeData);
        if (!success) revert CallFailed();
    }

    /* ========== SETTERS ========== */
    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert NotAllowed();

        governance = msg.sender;
        futureGovernance = address(0);

        emit GovernanceChanged(msg.sender);
    }

    /// @notice change strategy
    /// @param _newStrategy strategy address
    function changeStrategy(address _newStrategy) external onlyGovernance {
        angleStrategy = _newStrategy;
    }
}
