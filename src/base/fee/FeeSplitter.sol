// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IAccumulator} from "src/base/interfaces/IAccumulator.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

/// @title A contract that receive token at every strategy harvest
/// @author StakeDAO
contract FeeSplitter {
    uint256 public constant BASE_FEE = 10_000;

    /// @notice accumulator address
    address public immutable accumulator;

    /// @notice dao address
    address public immutable dao;

    /// @notice token address.
    address public immutable token;

    /// @notice veSdtFeeProxy address
    address public immutable veSdtFeeProxy;

    /// @notice accumulator part (10_000 = 100%)
    uint256 public immutable accumulatorFee;

    /// @notice dao part (10_000 = 100%)
    uint256 public immutable daoFee;

    /// @notice veSdtFeeProxy part (10_000 = 100%)
    uint256 public immutable veSdtFeeProxyFee;

    error ONLY_ACCUMULATOR();

    modifier onlyAccumulator() {
        if (msg.sender != accumulator) revert ONLY_ACCUMULATOR();
        _;
    }

    constructor(address _accumulator, address _token, address _veSdtFeeProxy, address _dao) {
        token = _token;
        accumulator = _accumulator;
        dao = _dao;
        veSdtFeeProxy = _veSdtFeeProxy;
        accumulatorFee = 5_000; // 50%
        daoFee = 2_500; // 25%
        veSdtFeeProxyFee = 2_500; // 25%
    }

    function split() external onlyAccumulator {
        uint256 amount = ERC20(token).balanceOf(address(this));
        if (amount == 0) {
            return;
        }

        // DAO part
        uint256 daoPart = amount * daoFee / BASE_FEE;
        SafeTransferLib.safeTransfer(token, dao, daoPart);

        // Accumulator part
        uint256 accumulatorPart = amount * accumulatorFee / BASE_FEE;
        SafeTransferLib.safeTransfer(token, accumulator, accumulatorPart);

        // VeSdtFeeProxy part
        uint256 veSdtFeeProxyPart = amount * veSdtFeeProxyFee / BASE_FEE;
        SafeTransferLib.safeTransfer(token, veSdtFeeProxy, veSdtFeeProxyPart);
    }
}
