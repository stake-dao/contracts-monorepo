// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BaseSetup, IStrategy} from "test/BaseSetup.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeLibrary} from "test/utils/SafeLibrary.sol";
import {RewardVault} from "src/RewardVault.sol";
import {RewardReceiver} from "src/RewardReceiver.sol";
import {Accountant} from "src/Accountant.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {Strategy} from "src/Strategy.sol";
import {Allocator} from "src/Allocator.sol";
import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";
import {Enum} from "@safe/contracts/common/Enum.sol";

/// @title BaseIntegrationTest - Protocol-Agnostic Integration Test Framework
/// @notice Abstract base test contract that captures universal DeFi reward distribution invariants.
/// @dev Provides a common testing framework for all protocol integrations.
///      Key features:
///      - Standardized deposit/withdraw/claim cycles.
///      - Multi-user and multi-gauge testing support.
///      - Comprehensive reward distribution validation.
///      - Protocol-agnostic test structure.
abstract contract NewBaseIntegrationTest is BaseSetup {}
