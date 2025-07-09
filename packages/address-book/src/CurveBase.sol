// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library CurveProtocol {
    address internal constant CRV = 0x8Ee73c484A26e0A5df2Ee2a4960B789967dd0415;
    /// The factory is also the Minter.
    address internal constant FACTORY = 0xe35A879E5EfB4F1Bb7F70dCF3250f2e19f096bd8;
    address internal constant VECRV = 0xeB896fB7D1AaE921d586B0E5a037496aFd3E2412;
}

library CurveLocker {
    address internal constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
}

library CurveStrategy {
    address internal constant ACCOUNTANT = 0x93b4B9bd266fFA8AF68e39EDFa8cFe2A62011Ce0;
    address internal constant PROTOCOL_CONTROLLER = 0x2d8BcE1FaE00a959354aCD9eBf9174337A64d4fb;
    address internal constant GATEWAY = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;

    address internal constant STRATEGY = 0x7D0775442d5961AE7090e4EC6C76180e8EEeEf54;

    address internal constant FACTORY = 0x37B015FA4Ba976c57E8e3A0084288d9DcEA06003;
    address internal constant ALLOCATOR = 0x17C23b24A7a5603BbfE5aa38A26A4F6a7E04B14b;

    address internal constant REWARD_VAULT_IMPLEMENTATION = 0x74D8dd40118B13B210D0a1639141cE4458CAe0c0;
    address internal constant REWARD_RECEIVER_IMPLEMENTATION = 0x4E35037263f75F9fFE191B5f9B5C7cd0c3169019;
}