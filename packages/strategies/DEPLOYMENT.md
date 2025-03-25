# Curve Strategy Deployment (Mainnet)

This document contains the deployment information for the Curve Strategy contracts on Ethereum mainnet. These addresses are for testing purposes.

## Core Contracts

| Contract | Address | Source Code |
|----------|---------|-------------|
| CurveStrategy | [`0x3F90BB1CB9D5b48856EaC9c56Ed70ed7A4D07A03`](https://etherscan.io/address/0x3F90BB1CB9D5b48856EaC9c56Ed70ed7A4D07A03) | [CurveStrategy.sol](./src/integrations/curve/CurveStrategy.sol) |
| CurveFactoryHarness | [`0xc6c9719d0e6a9a5aa21b6909211f112f60893112`](https://etherscan.io/address/0xc6c9719d0e6a9a5aa21b6909211f112f60893112) | [Deploy.s.sol](./script/curve/mainnet/Deploy.s.sol) |

## Dependencies & Related Contracts

| Contract | Address | Source Code | Description |
|----------|---------|-------------|-------------|
| Protocol Controller | [`0xb3723688250cAa0413e9C2c47123aA24Dd0265d0`](https://etherscan.io/address/0xb3723688250cAa0413e9C2c47123aA24Dd0265d0) | [ProtocolController.sol](./src/core/ProtocolController.sol) | Main controller for the protocol |
| Gateway | [`0xFd05F919e139544312A69b7DfB445E775824a31C`](https://etherscan.io/address/0xFd05F919e139544312A69b7DfB445E775824a31C) | [Gateway.sol](./src/core/Gateway.sol) | Gateway contract |
| Reward Vault Implementation | [`0xd0e17DF211bEBbD57738F21737D9Dd30C7e77353`](https://etherscan.io/address/0xd0e17DF211bEBbD57738F21737D9Dd30C7e77353) | [RewardVault.sol](./src/vaults/RewardVault.sol) | Implementation for reward vaults |
| Reward Receiver Implementation | [`0xbe65a5DE37Bb6C3f58b793f8D976Bc54523733E3`](https://etherscan.io/address/0xbe65a5DE37Bb6C3f58b793f8D976Bc54523733E3) | [RewardReceiver.sol](./src/vaults/RewardReceiver.sol) | Implementation for reward receivers |
| Convex Sidecar Factory | [`0xa8EbaCd98CB7022961a544BCcDeeF2364d065f51`](https://etherscan.io/address/0xa8EbaCd98CB7022961a544BCcDeeF2364d065f51) | [ConvexSidecarFactory.sol](./src/integrations/curve/ConvexSidecarFactory.sol) | Factory for Convex sidecars |
| CRV Token | [`0xD533a949740bb3306d119CC777fa900bA034cd52`](https://etherscan.io/address/0xD533a949740bb3306d119CC777fa900bA034cd52) | [CRV.sol](https://etherscan.io/token/0xD533a949740bb3306d119CC777fa900bA034cd52#code) | Curve DAO Token |
| Minter Contract | [`0xd061D61a4d941c39E5453435B6345Dc261C2fcE0`](https://etherscan.io/address/0xd061D61a4d941c39E5453435B6345Dc261C2fcE0) | [Minter.vy](https://etherscan.io/address/0xd061D61a4d941c39E5453435B6345Dc261C2fcE0#code) | Curve Token Minter |

## Notes

- This deployment is for testing purposes
- The CurveFactoryHarness is a test version of the CurveFactory with modified validation
- All contracts are verified on Etherscan
- Deployment was executed from address: [`0xf1c9775ef36e1f633c362e3011589ac9781ab0ff`](https://etherscan.io/address/0xf1c9775ef36e1f633c362e3011589ac9781ab0ff)

## Protocol Configuration

The following configurations were made during deployment:
- Protocol ID: `CURVE`
- CRV Token: [`0xD533a949740bb3306d119CC777fa900bA034cd52`](https://etherscan.io/address/0xD533a949740bb3306d119CC777fa900bA034cd52)
- Minter Contract: [`0xd061D61a4d941c39E5453435B6345Dc261C2fcE0`](https://etherscan.io/address/0xd061D61a4d941c39E5453435B6345Dc261C2fcE0)