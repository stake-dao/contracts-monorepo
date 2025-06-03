# Stake DAO V2 — System Specification

## 1. System Architecture Overview

Stake DAO V2 is a modular, gas-efficient yield optimization protocol designed to source rewards from various DeFi platforms (Curve, Balancer, Pendle, etc.) while providing a unified user experience. The system employs a component-based architecture with clear separation of concerns to enable flexible reward streaming, multi-chain deployment, and seamless protocol integrations.

![System Architecture Diagram](https://hackmd.io/_uploads/B1DB63Kske.png)

### Core Design Principles

1. **Modularity**: Each component has a single responsibility and well-defined interfaces
2. **Gas Efficiency**: Optimized storage layouts and integral-based reward calculations
3. **Extensibility**: Protocol-agnostic design allows for easy integration with new yield sources
4. **Security**: Multi-layered permission system and emergency shutdown capabilities

## 2. Core Components

### 2.1 ProtocolController

The ProtocolController serves as the central registry and permission management system for the entire protocol.

**Key Responsibilities:**

- Maintains a registry of all protocol components (Vaults, Strategies, Allocators, etc.)
- Manages permissions through a flexible access control system
- Provides emergency shutdown capabilities at both protocol and gauge levels
- Enables component upgradability without full system redeployment

**Technical Implementation:**

- Uses a bytes4 protocol ID to identify different protocol integrations
- Implements a permission system with granular function-level access control
- Stores component addresses in optimized storage structures

### 2.2 Vaults (RewardVault)

Vaults are the primary user entry points for depositing and withdrawing assets.

**Key Responsibilities:**

- Implements ERC4626 standard for maximum composability
- Coordinates with Allocator to determine optimal asset deployment
- Notifies Accountant of user actions (deposits, withdrawals, transfers)
- Manages additional reward tokens beyond the primary protocol reward

**Technical Implementation:**

- Extends ERC20 with ERC4626 functionality
- Uses clone factory pattern for efficient deployment
- Delegates reward accounting to the Accountant contract
- Support for additional reward tokens per vault

### 2.3 Allocator

The Allocator determines the optimal distribution of deposited funds across multiple yield strategies.

**Key Responsibilities:**

- Calculates optimal allocation of assets across different targets
- Provides allocation information for deposits, withdrawals, and rebalances
- Maintains a list of allocation targets for each gauge

**Technical Implementation:**

- Base implementation directs all funds to a single target (LOCKER)
- Protocol-specific implementations (e.g., CurveAllocator) can override allocation logic
- Returns structured Allocation objects containing targets and amounts

### 2.4 Strategy

Strategies implement the protocol-specific logic for interacting with external yield sources.

**Key Responsibilities:**

- Executes deposit and withdrawal operations through protocol-specific implementations
- Harvests and reports rewards from external protocols
- Manages interactions with Sidecar contracts for additional integrations
- Provides balance tracking across multiple allocation targets

**Technical Implementation:**

- Abstract base contract with protocol-specific implementations
- Uses a gateway/module manager pattern for executing transactions
- Implements virtual functions for protocol-specific operations
- Tracks pending rewards through the PendingRewards structure

### 2.5 Accountant

The Accountant is the central reward management system, handling reward distribution and fee calculations.

**Key Responsibilities:**

- Tracks user balances and rewards across all vaults using integral-based accounting
- Manages two reward streams: checkpoint rewards and harvested rewards
- Handles protocol fee collection and distribution

**Technical Implementation:**

- Uses gas-optimized packed storage for efficient reward tracking
- Implements integral-based reward calculation for precise per-user accounting
- Provides checkpoint operations for immediate reward updates
- Manages harvest operations for batch reward processing

### 2.6 Gateway (Safe Multisig)

The Gateway serves as a unified transaction execution layer for the protocol.

**Key Responsibilities:**

- Provides a consistent interface for executing transactions across multiple DeFi platforms
- Manages permissions for transaction execution
- Ensures secure interaction with external protocols

**Technical Implementation:**

- Implements Safe Multisig functionality
- Uses module manager pattern for transaction execution
- Provides standardized transaction execution interface

### 2.7 Sidecar

Sidecars provide protocol-specific integrations for external yield sources.

**Key Responsibilities:**

- Implements protocol-specific logic for interacting with external protocols
- Provides a standardized interface for deposits, withdrawals, and reward claiming
- Enables independent upgrades for protocol integrations

**Technical Implementation:**

- Abstract base contract with protocol-specific implementations
- Implements virtual functions for protocol-specific operations
- Uses a standardized interface for interaction with Strategy contracts

## 3. Core Processes

### 3.1 Reward Distribution Mechanism

Stake DAO V2 implements a dual reward stream system to balance immediate reward availability with gas efficiency.

#### 3.1.1 Checkpoint Rewards

Checkpoint rewards are processed immediately upon user actions (deposit, withdrawal, or transfer).

**Process Flow:**

1. User performs an action (deposit, withdrawal, or transfer)
2. Vault calls Accountant.checkpoint() with the action details
3. Accountant updates the reward integral and user balances
4. User can immediately claim accrued rewards

**Technical Details:**

- Uses integral-based accounting for precise reward calculation
- Processes rewards with minimal gas overhead
- Updates user-specific reward state on each action

**Flow Diagram:**

```mermaid
---
config:
  theme: neo
  look: neo
  layout: dagre
---
flowchart TD
    subgraph User["User Actions"]
        A[User] -->|"Performs action"| B["RewardVault<br/>(deposit/withdraw/transfer)"]
    end



    subgraph Checkpoint["Checkpoint Process"]
        B -->|"Call checkpoint() with<br/>action details"| C[Accountant]
        C -->|"A. Get current timestamp"| D[["Reward Integral<br/>Calculation"]]
        D -->|"B. Calculate rewards<br/>since last update"| E["Update Global State<br/>- rewardPerTokenStored<br/>- lastUpdateTime"]
        E -->|"C. Update user state"| F["Update User Balances<br/>- rewardPerTokenPaid<br/>- claimable rewards"]
    end

    subgraph Reward["Reward Availability"]
        F -->|"Rewards ready"| G[User can claim<br/>accrued rewards]
        G -->|"Claim request"| H["Transfer rewards<br/>to user"]
    end

    %% External actors in pink
    style A fill:#f9f,stroke:#333,stroke-width:2px
    style G fill:#f9f,stroke:#333,stroke-width:2px
    style H fill:#f9f,stroke:#333,stroke-width:2px

    %% StakeDAO contracts in blue
    style B fill:#bbf,stroke:#333,stroke-width:2px
    style C fill:#bbf,stroke:#333,stroke-width:2px
    style D fill:#bbf,stroke:#333,stroke-width:2px
    style E fill:#bbf,stroke:#333,stroke-width:2px
    style F fill:#bbf,stroke:#333,stroke-width:2px

    %% Subgraphs
    style User fill:#fff,stroke:#bbf,stroke-width:2px
    style Checkpoint fill:#fff,stroke:#bbf,stroke-width:2px
    style Reward fill:#fff,stroke:#bbf,stroke-width:2px

    %% Process nodes formatting
    classDef processNode text-align:center,font-size:12px
    class B,C,D,E,F,G,H processNode
```

#### 3.1.2 Harvested Rewards

Harvested rewards are batch-processed when gas-efficient, according to governance-defined thresholds.

**Process Flow:**

1. Pending rewards accumulate in the Accountant
2. A harvest operation is triggered
3. Strategy claims rewards from external protocols
4. Accountant distributes rewards to users based on their share of the vault

**Technical Details:**

- Uses PendingRewards structure to track reward amounts
- Separates fee-subject amounts from total reward amounts

### 3.2 Fee Structure

The protocol implements a flexible fee structure.

#### 3.2.1 Harvest Fee (0.5%)

Fixed fee to all rewards to cover gas cost of the caller.

#### 3.2.2 Protocol Fee (15%)

Fixed fee applied to all rewards to fund protocol operations and development.

**Implementation:**

- Applied to fee-subject amounts only
- Accrued in the Accountant contract
- Claimable by the designated fee receiver

#### 3.2.3 Fee Cap (40%)

All fees combined (harvest + protocol) cannot exceed 40% of rewards.

### 3.3 Deposit Flow

**Process Flow:**

1. User deposits tokens into a Vault
2. Vault updates reward state via Accountant.checkpoint()
3. Vault consults Allocator to determine optimal asset distribution
4. Assets are transferred to the designated targets
5. Strategy executes deposit operations through protocol-specific implementations
6. Vault mints shares to the user

**Technical Details:**

- Uses ERC4626 standard for deposits
- Implements allocation-based deposit strategy
- Updates reward state before processing deposit

**Flow Diagram:**

```mermaid
---
config:
  theme: neo
  look: neo
  layout: dagre
---
flowchart TD
    subgraph User["User Operations"]
        A["User"]
        M["Receiver obtains vault tokens"]
    end

    subgraph RewardVault["RewardVault Contract"]
        B["RewardVault"]
        C["Update internal reward state"]
        D["Fetch deposit allocation"]
        AT["Transfer assets directly<br/>to allocation targets"]
        SP["Process deposit via Strategy"]
    end

    subgraph Allocator["Allocator Contract"]
        AL["Calculate deposit allocation<br/>- Target addresses<br/>- Amount per target"]
    end

    subgraph Strategy["Strategy Contract"]
        E["Process deposits"]
        F{"For each target"}
        G["Deposit to Locker"]
        H["Deposit to Sidecar"]
        HR["Harvest rewards"]
        HL["Harvest from Locker"]
        HS["Harvest from Sidecar"]
    end

    subgraph Accountant["Accountant Contract"]
        AC["Checkpoint & mint shares<br/><br/>Process pending rewards"]
    end

    subgraph External["External Protocols"]
        L1["Locker"]
        L2["Protocol via Sidecar"]
    end

    %% Flow connections
    A -->|"Deposits tokens for the receiver."| B
    B --> C
    B --> D
    D --> AL
    AL --> AT
    AT --> SP
    SP --> E
    E --> F
    F -->|"if target = LOCKER"| G
    F -->|"if target = Sidecar"| H
    G --> L1
    H --> L2
    E --> HR
    HR --> HL & HS
    HL --> L1
    HS --> L2
    HL & HS --> AC
    AC --> M

    %% External protocols in red
    style L1 fill:#fdd,stroke:#333,stroke-width:2px
    style L2 fill:#fdd,stroke:#333,stroke-width:2px

    %% StakeDAO contracts in blue
    style B fill:#bbf,stroke:#333,stroke-width:2px
    style C fill:#bbf,stroke:#333,stroke-width:2px
    style D fill:#bbf,stroke:#333,stroke-width:2px
    style AT fill:#bbf,stroke:#333,stroke-width:2px
    style SP fill:#bbf,stroke:#333,stroke-width:2px
    style AL fill:#bbf,stroke:#333,stroke-width:2px
    style E fill:#bbf,stroke:#333,stroke-width:2px
    style F fill:#bbf,stroke:#333,stroke-width:2px
    style G fill:#bbf,stroke:#333,stroke-width:2px
    style H fill:#bbf,stroke:#333,stroke-width:2px
    style HR fill:#bbf,stroke:#333,stroke-width:2px
    style HL fill:#bbf,stroke:#333,stroke-width:2px
    style HS fill:#bbf,stroke:#333,stroke-width:2px
    style AC fill:#bbf,stroke:#333,stroke-width:2px

    %% Users in pink
    style A fill:#f9f,stroke:#333,stroke-width:2px
    style M fill:#f9f,stroke:#333,stroke-width:2px

    %% Subgraph styling
    style User fill:#fff,stroke:#f9f,stroke-width:2px
    style RewardVault fill:#fff,stroke:#bbf,stroke-width:2px
    style Strategy fill:#fff,stroke:#bbf,stroke-width:2px
    style Allocator fill:#fff,stroke:#bbf,stroke-width:2px
    style Accountant fill:#fff,stroke:#bbf,stroke-width:2px
    style External fill:#fff,stroke:#fdd,stroke-width:2px

    %% Process nodes formatting
    classDef processNode text-align:center,font-size:12px
    class A,B,C,D,AT,SP,AL,E,F,G,H,HR,HL,HS,L1,L2,M,AC processNode
```

### 3.4 Withdrawal Flow

**Process Flow:**

1. User requests withdrawal from a Vault
2. Vault updates reward state via Accountant.checkpoint()
3. Vault consults Allocator to determine withdrawal sources
4. Strategy executes withdrawal operations through protocol-specific implementations
5. Assets are transferred to the user
6. Vault burns shares from the user

**Technical Details:**

- Uses ERC4626 standard for withdrawals
- Implements allocation-based withdrawal strategy
- Updates reward state before processing withdrawal

**Flow Diagram:**

```mermaid
---
config:
  theme: neo
  look: neo
  layout: dagre
---
flowchart TD
    subgraph User["User Operations"]
        U1["Initiates withdrawal"]
        U2["Receiver"]
    end

    subgraph RewardVault["RewardVault Contract"]
        R1["Update reward state<br/>via checkpoint"]
        R2["Get withdrawal allocation<br/>from Allocator"]
        R3["Call Strategy to<br/>process withdrawal"]
        R4["Burn shares via<br/>Accountant checkpoint"]
        R5["Transfer underlying<br/>assets to receiver"]
    end

    subgraph Allocator["Allocator Contract"]
        A1["Calculate optimal<br/>withdrawal distribution"]
        A2["Return withdrawal targets<br/>and amounts"]
    end

    subgraph Strategy["Strategy Contract"]
        S1["Process withdrawal<br/>for each target"]
        S2["If target is Locker:<br/>Direct withdrawal"]
        S3["If target is Sidecar:<br/>Protocol-specific withdrawal"]
        S4["Calculate pending rewards by syncing or harvest rewards<br/><i>(based on doHarvest flag)</i>"]
    end

    subgraph Accountant["Accountant Contract"]
        AC1["Update user balance"]
        AC2["Update reward state"]
        AC3["Process pending rewards<br/>if harvested"]
    end

    subgraph External["External Protocol"]
        E1["Release staked/locked<br/>assets"]
    end

    %% Flow connections
    U1 --> R1
    R1 --> R2
    R2 --> A1
    A1 --> A2
    A2 --> R3
    R3 --> S1
    S1 --> S2
    S1 --> S3
    S2 & S3 --> E1
    E1 --> S4
    S4 --> R4
    R4 --> AC1
    AC1 --> AC2
    AC2 --> AC3
    R4 --> R5
    R5 --> U2

    %% Styling
    %% External protocols in red
    style E1 fill:#fdd,stroke:#333,stroke-width:2px

    %% StakeDAO contracts in blue
    style R1 fill:#bbf,stroke:#333,stroke-width:2px
    style R2 fill:#bbf,stroke:#333,stroke-width:2px
    style R3 fill:#bbf,stroke:#333,stroke-width:2px
    style R4 fill:#bbf,stroke:#333,stroke-width:2px
    style R5 fill:#bbf,stroke:#333,stroke-width:2px
    style A1 fill:#bbf,stroke:#333,stroke-width:2px
    style A2 fill:#bbf,stroke:#333,stroke-width:2px
    style S1 fill:#bbf,stroke:#333,stroke-width:2px
    style S2 fill:#bbf,stroke:#333,stroke-width:2px
    style S3 fill:#bbf,stroke:#333,stroke-width:2px
    style S4 fill:#bbf,stroke:#333,stroke-width:2px
    style AC1 fill:#bbf,stroke:#333,stroke-width:2px
    style AC2 fill:#bbf,stroke:#333,stroke-width:2px
    style AC3 fill:#bbf,stroke:#333,stroke-width:2px

    %% Users in pink
    style U1 fill:#f9f,stroke:#333,stroke-width:2px

    %% Subgraph styling
    style User fill:#fff,stroke:#f9f,stroke-width:2px
    style RewardVault fill:#fff,stroke:#bbf,stroke-width:2px
    style Strategy fill:#fff,stroke:#bbf,stroke-width:2px
    style Allocator fill:#fff,stroke:#bbf,stroke-width:2px
    style Accountant fill:#fff,stroke:#bbf,stroke-width:2px
    style External fill:#fff,stroke:#fdd,stroke-width:2px

    %% Process nodes formatting
    classDef processNode text-align:center,font-size:12px
    class U1,R1,R2,R3,R4,R5,A1,A2,S1,S2,S3,S4,AC1,AC2,AC3,E1 processNode
```

### 3.5 Harvest Mechanism

**Process Flow:**

1. Harvester reviews pending rewards in the Accountant
3. Strategy harvests rewards from external protocols
4. Accountant processes rewards, deducting fees
5. Users can claim their share of rewards

**Technical Details:**

- Implements batch harvesting for gas efficiency
- Uses dynamic fee calculation based on reward balance
- Separates fee-subject amounts from total reward amounts

**Flow Diagram:**

```mermaid
---
config:
  theme: neo
  look: neo
  layout: dagre
---
flowchart TD
    subgraph External["External Protocol"]
        A["Protocol Gauge/Pool"] -->|"Generate rewards"| B["Unclaimed Protocol Rewards"]
    end

    subgraph Accountant["Accountant Contract"]
        A1["Initiate Harvest"] -->A2{"Calculate Current<br/>Harvest Fee"}
        A2 -->|"Threshold = 0"| A3["Max fee (0.5%)"]
        A2 -->|"Balance ≥ Threshold"| A4["No fee (0%)"]
        A2 -->|"Balance < Threshold"| A5["Scale fee linearly"]
        A3 & A4 & A5 --> A6["Process each gauge"]
        A6 -->|"For each gauge"| A7["Update reward state<br/>- Update integral<br/>- Update netCredited"]
    end

    subgraph Strategy["Strategy Contract"]
        S1["Claim Protocol Rewards"]
        S1 --> S3["Calculate accumulated rewards"]
        S3 --> S4["Store rewards in<br/>transient storage<br/>(deferRewards=true)"]
        S5["Flush accumulated rewards<br/>after all gauges processed"]
    end

    subgraph Processing["Fee Processing"]
        P1["Process accumulated rewards"] -->|"Apply fees"| P2["Calculate total fees<br/>- Harvest fee (pre-calculated)<br/>- Protocol fee (15%)<br/>- Total cap (40%)"]
        P2 -->|"Transfer fees"| P3["Send harvester fee<br/>to receiver"]
    end

    %% Inter-contract flows
    B -->|"Available to claim"| S1
    A6 -->|"Call harvest() for each gauge"| S1
    A7 --> |"After all gauges processed"| S5
    S5 -->|"Single transfer of all rewards"| P1
    P3 --> R["Users can claim<br/>their share"]

    %% External protocols in red
    style A fill:#fdd,stroke:#333,stroke-width:2px
    style B fill:#fdd,stroke:#333,stroke-width:2px

    %% StakeDAO contracts in blue
    style A1 fill:#bbf,stroke:#333,stroke-width:2px
    style A2 fill:#bbf,stroke:#333,stroke-width:2px
    style A3 fill:#bbf,stroke:#333,stroke-width:2px
    style A4 fill:#bbf,stroke:#333,stroke-width:2px
    style A5 fill:#bbf,stroke:#333,stroke-width:2px
    style A6 fill:#bbf,stroke:#333,stroke-width:2px
    style A7 fill:#bbf,stroke:#333,stroke-width:2px
    style S1 fill:#bbf,stroke:#333,stroke-width:2px
    style S3 fill:#bbf,stroke:#333,stroke-width:2px
    style S4 fill:#bbf,stroke:#333,stroke-width:2px
    style S5 fill:#bbf,stroke:#333,stroke-width:2px
    style P1 fill:#bbf,stroke:#333,stroke-width:2px
    style P2 fill:#bbf,stroke:#333,stroke-width:2px
    style P3 fill:#bbf,stroke:#333,stroke-width:2px

    %% Users in pink
    style R fill:#f9f,stroke:#333,stroke-width:2px

    %% Subgraph styling
    style External fill:#fff,stroke:#fdd,stroke-width:2px
    style Strategy fill:#fff,stroke:#bbf,stroke-width:2px
    style Accountant fill:#fff,stroke:#bbf,stroke-width:2px
    style Processing fill:#fff,stroke:#bbf,stroke-width:2px

    %% Process nodes formatting
    classDef processNode text-align:center,font-size:12px
    class A,B,S1,S3,S4,S5,A1,A2,A3,A4,A5,A6,A7,P1,P2,P3,R processNode
```

## 4. Integration Guide

### 4.1 Adding a New Protocol Integration

To integrate a new yield protocol with Stake DAO V2:

1. **Define Protocol ID**

   - Create a unique bytes4 identifier for the protocol

2. **Implement Strategy**

   - Extend the base Strategy contract
   - Implement protocol-specific deposit, withdraw, and harvest functions
   - Define reward synchronization logic

3. **Implement Allocator**

   - Extend the base Allocator contract
   - Define allocation logic for the protocol
   - Implement target selection for deposits and withdrawals

4. **Implement Sidecar (if needed)**

   - Extend the base Sidecar contract
   - Implement protocol-specific interactions
   - Define reward claiming logic

5. **Register Components**
   - Register components with ProtocolController
   - Set up permissions for component interactions
   - Configure fee parameters

### 4.2 Vault Deployment

To deploy a new vault for an existing protocol integration:

1. **Identify Target Gauge**

   - Select the gauge/pool to integrate with

2. **Deploy Vault**

   - Use the RewardVault implementation
   - Configure with appropriate protocol ID and gauge

3. **Register Vault**
   - Register the vault with ProtocolController
   - Set up reward tokens and distributors

### 4.3 Protocol-Specific Considerations

When integrating with specific protocols, consider:

1. **Boost Mechanisms**

   - Configure optimal boost allocation

2. **Reward Claiming**

   - Implement protocol-specific reward claiming logic
   - Handle multiple reward tokens if necessary

3. **Security Constraints**
   - Respect protocol-specific security requirements
   - Implement appropriate validation checks

## 5. Security Considerations

### 5.1 Permission System

The protocol implements a granular permission system through ProtocolController:

- Function-level permissions for contract interactions
- Designated permission setters for managing access
- Owner-controlled critical functions

### 5.2 Emergency Shutdown

Two levels of emergency shutdown are available:

1. **Gauge Shutdown**

   - Disables operations for a specific gauge
   - Allows users to withdraw funds

2. **Protocol Shutdown**
   - Disables all operations for a protocol integration
   - Affects all gauges associated with the protocol

### 5.3 Reentrancy Protection

The protocol implements reentrancy protection through:

- ReentrancyGuardTransient for critical functions
- Proper check-effects-interactions pattern
- Safe external calls

## 6. Roadmap

### 6.1 Deployment Standardization

**Objective:** Ensure the V2 system design is modular and flexible for deployment on any yield source.

**Implementation Plan:**

- Standardize interfaces for protocol integrations
- Develop adapter patterns for new yield protocols
- Create deployment templates for rapid integration

### 6.2 CollateralWrapper & Factory for Lending Markets

**Objective:** Enable vault positions to be used as collateral in lending markets.

**Implementation Plan:**

- Develop CollateralWrapper contract to tokenize vault positions
- Implement Factory pattern for automated wrapper deployment
- Create adapters for major lending protocols (Morpho, Inverse, etc.)

### 6.3 Developer Experience Improvements

**Objective:** Minimize integration overhead for protocols to leverage Stake DAO yields.

**Implementation Plan:**

- Create detailed documentation and integration guides
- Provide reference implementations for common use cases

## 7. Glossary

- **Gauge:** External protocol's staking contract (e.g., Curve Gauge)
- **Vault:** User-facing contract for deposits and withdrawals
- **Strategy:** Protocol-specific implementation for yield generation
- **Allocator:** Component that determines optimal asset allocation
- **Accountant:** Central reward tracking and distribution system
- **Sidecar:** Protocol-specific adapter for external integrations
- **Gateway:** Transaction execution layer for external interactions
- **Checkpoint Rewards:** Immediately accessible rewards from user actions
- **Harvested Rewards:** Batch-processed rewards for gas efficiency
