// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library CurveProtocol {
    address internal constant CRV = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978;
    /// The factory is also the Minter.
    address internal constant FACTORY = 0xabC000d88f23Bb45525E447528DBF656A9D55bf5;
}

library CurveVotemarket {
    address internal constant PLATFORM = 0x8c2c5A295450DDFf4CB360cA73FCCC12243D14D9;
}