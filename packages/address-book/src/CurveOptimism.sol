// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library CurveProtocol {
    address internal constant CRV = 0x0994206dfE8De6Ec6920FF4D779B0d950605Fb53;
    /// The factory is also the Minter.
    address internal constant FACTORY = 0xabC000d88f23Bb45525E447528DBF656A9D55bf5;
    address internal constant VECRV = 0xF1946D4879646e0FCD8F5bb32a5636ED8055176D;
}

library CurveLocker {
    address internal constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
}