// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.28;

// import {PendleMainnetIntegrationTest} from "test/integration/pendle/mainnet/PendleMainnetIntegration.t.sol";
// import {PendleProtocol, PendleLocker} from "@address-book/src/PendleEthereum.sol";
// import {IStrategy} from "src/interfaces/IStrategy.sol";

// contract PendleBaseIntegrationTest is PendleMainnetIntegrationTest {
//     Config public _config = Config({
//         base: BaseConfig({
//             chain: "mainnet", // TODO: change to base
//             blockNumber: 22_982_312, // TODO: change to base
//             rewardToken: PendleProtocol.PENDLE,
//             locker: PendleLocker.LOCKER,
//             protocolId: bytes4(keccak256("PENDLE")),
//             harvestPolicy: IStrategy.HarvestPolicy.HARVEST,
//             gaugeController: PendleProtocol.GAUGE_CONTROLLER,
//             oldStrategy: PendleLocker.STRATEGY // TODO: change to base
//         })
//     });
// }
