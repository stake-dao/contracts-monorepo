# Guidelines for Smart Contracts Development

## Paths

Always privilege full path such as:

```js
import "src/interfaces/IInterface.sol"
```

To avoid:

```js
import "../../IInterface.sol"
```

If you need only specific contract, import that specific and not the full file and dependancies:

```js
import { IInterface } from "src/interfaces/IInterface.sol"
```

## Comments

Natspect everything:

```js
/// @title  Counter
/// @notice Describe what the contract does
/// @author Stake DAO (Labs ?)
/// @custom:contact contact@stakedao.org
contract Counter {
    /// @notice Describe what this variable does
    uint256 public number;

    /// @notice Describe what this function does
    /// @param newNumber Describe this parameter
    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    /// @notice Describe what this function does
    function increment() public {
        number++;
    }
}
```

Separator between code logic:

```js
////////////////////////////////////////////////////////////////
/// --- DEPOSIT/WITHDRAW
///////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////
/// --- REWARDS MANAGEMENT
///////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////
/// --- GOVERNANCE PARAMETERS
///////////////////////////////////////////////////////////////
````

## External Libraries

* Avoid mixing libraries, if you start with solmate, use Solmate.
    Example: Having a file with an ERC20 from solmate but a SafeTransfer from openzeppelin.

* Avoid mixing patterns between repo. If our repos uses mostly Auth.sol for Governance rights, Admin functions, keep it that way.
    Example: For example, we have the SDT Distributor using ROLES from openzeppelin but every other of our contracts uses regular onlyOwner.

* All the dependancies we need are in the lib/ folder. Other dependancies must be discussed with the team. Goal is to stay minimal and simple, it is better for simplicity/security reasons.

## Code

* Always standardize your code. Unless the implementation is focused for a use-case, platform only, we need to standardize our code, for better readability, efficience, reusability and frontend implementation.

Good:

```js
/// @title  Locker
/// @notice Describe what the contract does
/// @author Stake DAO (Labs ?)
/// @custom:contact contact@stakedao.org
contract Locker {
    /// @notice Describe what this variable does
    address public immutable token;

    /// @notice Describe what this variable does
    address public immutable veToken;
    }
}
```

To avoid:

```js
/// @title  Angle Locker
/// @notice Describe what the contract does
/// @author Stake DAO (Labs ?)
/// @custom:contact contact@stakedao.org
contract AngleLocker {
    /// @notice Describe what this variable does
    address public immutable ANGLE;

    /// @notice Describe what this variable does
    address public immutable veANGLE;
    }
}
```

* Use Custom Errors with explicit names.
* Clean the code. Always think for the people that will read your code afterwards, they need to understand it as good as you understand it without so much effort.

Good:

```js
function exchange(
        address aggregator,
        address srcToken,
        address destToken,
        uint256 underlyingAmount,
        bytes memory callData
    ) external payable onlyValidAggregator(aggregator) returns (uint256 received) {
        bool success;
        uint256 before = destToken == Constants._ETH ? address(this).balance : ERC20(destToken).balanceOf(address(this));

        if (srcToken == Constants._ETH) {
            (success,) = aggregator.call{value: underlyingAmount}(callData);
        } else {
            TokenUtils._approve(srcToken, aggregator, underlyingAmount);
            (success,) = aggregator.call(callData);
        }

        if (!success) revert SWAP_FAILED();

        if (destToken == Constants._ETH) {
            received = address(this).balance - before;
        } else {
            received = ERC20(destToken).balanceOf(address(this)) - before;
        }
    }
```

To Avoid:

```js
function exchange(
        address aggregator,
        address srcToken,
        address destToken,
        uint256 underlyingAmount,
        bytes memory callData
    ) external payable onlyValidAggregator(aggregator) returns (uint256 received) {
        bool success;
        uint256 before = destToken == Constants._ETH ? address(this).balance : ERC20(destToken).balanceOf(address(this));
        if (srcToken == Constants._ETH) {
            (success,) = aggregator.call{value: underlyingAmount}(callData);
        } else {
            TokenUtils._approve(srcToken, aggregator, underlyingAmount);
            (success,) = aggregator.call(callData);
        }
        if (!success) revert SWAP_FAILED();
        if (destToken == Constants._ETH) {
            received = address(this).balance - before;
        } else {
            received = ERC20(destToken).balanceOf(address(this)) - before;
        }
    }
```

## Format

Use exclusively the default fmt command from Forge.

Every needed command is in the makefile. If you think about a command we should add, drop a PR.
Remember that it needs to fit all the repos and not only a specific use-case. If the latter, try to standardize it.

## Tests

Each contract must at least:

* Be covered at 100%
* Try to add fuzzing in your unit-tests routine.
* Included in one complete integration tests.
* If complex logic, hold one invariant that your contract must respect whatever the interaction. (Invariant testing)


## Deployment

* Each deployment must be followed by a release in order to track every deployment and associated commit easily.

## Github

* Commits: Respect the conventionnal commit system for a better git history.
<https://gist.github.com/qoomon/5dfcdf8eec66a051ecd85625518cfd13>
* Merge only using Github UI. A Merge action should only happens from a pull request.
* If your branch is outdated, prefer use rebase for a clean history. Don't hesitate to ask in the chat if you need help for the first times.
* Always use Gitflow (main, develop, feat/my-feat, fix/my-bug-01).

## Bonus: Esthetic

Let's have the most beautiful and cleanest contract deployed live.

Example:

```js
import {ILocker} from "src/interfaces/ILocker.sol";
import {ILiquidityGauge} from "src/ILiquidityGauge.sol";
import {IContractA} from "src/interfaces/IContractA.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
```

instead of:

```js
import {ILiquidityGauge} from "src/ILiquidityGauge.sol";
import {ILocker} from "src/interfaces/ILocker.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IContractA} from "src/interfaces/IContractA.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
```
