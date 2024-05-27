// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

/// @title VESDTRecipient - A contract to receive fees to feed VBMs.
/// @notice Temporary contract to accumulate fees for veSDT.
/// @author StakeDAO
contract VESDTRecipient {
    address public constant ADMIN = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    error GOVERNANCE();

    modifier onlyGovernance() {
        if (msg.sender != ADMIN) revert GOVERNANCE();
        _;
    }

    function collect(address token, address recipient) external onlyGovernance {
        uint256 amount = ERC20(token).balanceOf(address(this));
        if (amount == 0) {
            return;
        }

        SafeTransferLib.safeTransfer(token, recipient, amount);
    }
}
