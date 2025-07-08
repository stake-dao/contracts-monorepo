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