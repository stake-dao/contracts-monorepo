# Curve Strategy Deployment (Mainnet)

This document contains the deployment information for the Curve Strategy contracts on Ethereum mainnet. These addresses are for testing purposes.

## Core Contracts

| Contract | Address | Source Code | Description |
|----------|---------|-------------|-------------|
| Protocol Controller | [`0xb3723688250cAa0413e9C2c47123aA24Dd0265d0`](https://etherscan.io/address/0xb3723688250cAa0413e9C2c47123aA24Dd0265d0) | [ProtocolController.sol](./src/ProtocolController.sol) | Main controller for the protocol |
| Accountant | [`0x31B9d2Fc2BBf92239622e990B400a4920E1f9693`](https://etherscan.io/address/0x31B9d2Fc2BBf92239622e990B400a4920E1f9693) | [Accountant.sol](./src/Accountant.sol) | Protocol accountant |
| Gateway | [`0xbe65a5DE37Bb6C3f58b793f8D976Bc54523733E3`](https://etherscan.io/address/0xbe65a5DE37Bb6C3f58b793f8D976Bc54523733E3) | Safe Contract | Gateway contract |
| Reward Vault | [`0xFd05F919e139544312A69b7DfB445E775824a31C`](https://etherscan.io/address/0xFd05F919e139544312A69b7DfB445E775824a31C) | [RewardVault.sol](./src/RewardVault.sol) | Implementation for reward vaults |
| Reward Receiver | [`0xd0e17DF211bEBbD57738F21737D9Dd30C7e77353`](https://etherscan.io/address/0xd0e17DF211bEBbD57738F21737D9Dd30C7e77353) | [RewardReceiver.sol](./src/RewardReceiver.sol) | Implementation for reward receivers |
| CurveStrategy | [`0x204CB16D50Ca7997C684d14BA97109941Bf26c6f`](https://etherscan.io/address/0x204CB16D50Ca7997C684d14BA97109941Bf26c6f) | [CurveStrategy.sol](./src/integrations/curve/CurveStrategy.sol) | Main Curve strategy implementation |
| CurveFactoryHarness | [`0xc6c9719d0E6a9A5Aa21B6909211F112f60893112`](https://etherscan.io/address/0xc6c9719d0E6a9A5Aa21B6909211F112f60893112) | [CurveFactory.sol](./src/integrations/curve/CurveFactory.sol) | Test version of CurveFactory |
| ConvexSidecar | [`0x3F90BB1CB9D5b48856EaC9c56Ed70ed7A4D07A03`](https://etherscan.io/address/0x3F90BB1CB9D5b48856EaC9c56Ed70ed7A4D07A03) | [ConvexSidecar.sol](./src/integrations/curve/ConvexSidecar.sol) | Convex integration contract |
| Convex Sidecar Factory | [`0xa8EbaCd98CB7022961a544BCcDeeF2364d065f51`](https://etherscan.io/address/0xa8EbaCd98CB7022961a544BCcDeeF2364d065f51) | [ConvexSidecarFactory.sol](./src/integrations/curve/ConvexSidecarFactory.sol) | Factory for Convex sidecars |

## External Contracts

| Contract | Address | Source Code | Description |
|----------|---------|-------------|-------------|
| CRV Token | [`0xD533a949740bb3306d119CC777fa900bA034cd52`](https://etherscan.io/address/0xD533a949740bb3306d119CC777fa900bA034cd52) | [CRV.sol](https://etherscan.io/token/0xD533a949740bb3306d119CC777fa900bA034cd52#code) | Curve DAO Token |
| Minter Contract | [`0xd061D61a4d941c39E5453435B6345Dc261C2fcE0`](https://etherscan.io/address/0xd061D61a4d941c39E5453435B6345Dc261C2fcE0) | [Minter.vy](https://etherscan.io/address/0xd061D61a4d941c39E5453435B6345Dc261C2fcE0#code) | Curve Token Minter |

## Notes

- This deployment is for testing purposes
- The CurveFactoryHarness is a test version of the CurveFactory with modified validation
- All contracts are verified on Etherscan
- Deployment was executed from address: [`0xf1c9775ef36e1f633c362e3011589ac9781ab0ff`](https://etherscan.io/address/0xf1c9775ef36e1f633c362e3011589ac9781ab0ff)

## UI Integration

To integrate with the Curve Strategy:

1. Core Functions:
   - Deposit: `rewardVault.deposit(amount, receiver)`
   - Withdraw: `rewardVault.withdraw(amount, owner, receiver)`
   - Claim Rewards: `accountant.claim(gauges[], harvestData[])`

2. Factory Deployment:
   - Deploy new vault: `curveFactory.create(pid)` returns (vault, rewardReceiver, sidecar)
   - Deploy vault only: `curveFactory.createVault(gauge)` returns (vault, rewardReceiver)
   - Deploy sidecar: `convexSidecarFactory.create(gauge, pid)` returns sidecar
   Note: Gauge must not be shutdown on old strategy for deployment

3. Extra Rewards:
   - Get reward tokens: `rewardVault.getRewardTokens()`
   - Claim extra rewards: `convexSidecar.claimExtraRewards()`
   - Distribute rewards: `rewardReceiver.distributeRewards()`
   - Claim specific tokens: `rewardVault.claim(rewardTokens[], receiver)`

4. Available Rewards:
   - CRV rewards from Curve gauges
   - CVX rewards from Convex integration
   - Extra rewards specific to each pool

6. Important Notes:
   - All contracts require prior approval for token transfers
   - Rewards must be harvested before claiming
   - Multiple gauges can be managed simultaneously
   - Check gauge status before deployment
   - Extra rewards have a vesting period (1 week)

## Protocol Configuration

The following configurations were made during deployment:
- Protocol ID: `CURVE`
- CRV Token: [`0xD533a949740bb3306d119CC777fa900bA034cd52`](https://etherscan.io/address/0xD533a949740bb3306d119CC777fa900bA034cd52)
- Minter Contract: [`0xd061D61a4d941c39E5453435B6345Dc261C2fcE0`](https://etherscan.io/address/0xd061D61a4d941c39E5453435B6345Dc261C2fcE0)