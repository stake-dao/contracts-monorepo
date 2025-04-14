// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

library RouterIdentifierMapping {
    uint8 internal constant DEPOSIT = 0x00;
    uint8 internal constant WITHDRAW = 0x01;
    uint8 internal constant CLAIM = 0x02;
    uint8 internal constant MIGRATION_STAKE_DAO_V1 = 0x03;
    uint8 internal constant MIGRATION_CURVE_V1 = 0x04;
}
