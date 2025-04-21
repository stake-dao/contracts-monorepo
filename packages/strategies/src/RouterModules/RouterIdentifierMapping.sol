// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

library RouterIdentifierMapping {
    uint8 internal constant DEPOSIT = 0x00;
    uint8 internal constant WITHDRAW = 0x01;
    uint8 internal constant CLAIM = 0x02;
    uint8 internal constant MIGRATION_STAKE_DAO_V1 = 0x03;
    uint8 internal constant MIGRATION_CURVE = 0x04;
    uint8 internal constant MIGRATION_YEARN = 0x05;
}
