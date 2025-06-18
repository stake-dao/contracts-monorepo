// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library CommonUniversal {
    /// DEPLOYER
    address internal constant DEPLOYER_1 = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;

    // FACTORY
    address internal constant CREATE2_FACTORY = 0x0000000000FFe8B47B3e2130213B802212439497;
    address internal constant CREATE3_FACTORY = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    // SAFE
    address internal constant SAFE_PROXY_FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    address internal constant SAFE_SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address internal constant SAFE_L2_SINGLETON = 0xfb1bffC9d739B8D520DaF37dF666da4C687191EA;
    address internal constant SAFE_FALLBACK_HANDLER = 0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99;

    // LayerZero
    address internal constant LAYERZERO_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
}