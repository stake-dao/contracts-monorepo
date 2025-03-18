// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IWeightedPool2Tokens {
    struct NewPoolParams {
        address vault;
        string name;
        string symbol;
        address token0;
        address token1;
        uint256 normalizedWeight0;
        uint256 normalizedWeight1;
        uint256 swapFeePercentage;
        uint256 pauseWindowDuration;
        uint256 bufferPeriodDuration;
        bool oracleEnabled;
        address owner;
    }

    struct OracleAccumulatorQuery {
        uint8 variable;
        uint256 ago;
    }

    struct OracleAverageQuery {
        uint8 variable;
        uint256 secs;
        uint256 ago;
    }

    struct SwapRequest {
        uint8 kind;
        address tokenIn;
        address tokenOut;
        uint256 amount;
        bytes32 poolId;
        uint256 lastChangeBlock;
        address from;
        address to;
        bytes userData;
    }

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OracleEnabledChanged(bool enabled);
    event PausedStateChanged(bool paused);
    event SwapFeePercentageChanged(uint256 swapFeePercentage);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function approve(address spender, uint256 amount) external returns (bool);
    function decreaseApproval(address spender, uint256 amount) external returns (bool);
    function enableOracle() external;
    function increaseApproval(address spender, uint256 amount) external returns (bool);
    function onExitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] calldata balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes calldata userData
    ) external returns (uint256[] memory, uint256[] memory);
    function onJoinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] calldata balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes calldata userData
    ) external returns (uint256[] memory amountsIn, uint256[] memory dueProtocolFeeAmounts);
    function onSwap(SwapRequest calldata request, uint256 balanceTokenIn, uint256 balanceTokenOut)
        external
        returns (uint256);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function queryExit(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] calldata balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes calldata userData
    ) external returns (uint256 bptIn, uint256[] memory amountsOut);
    function queryJoin(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] calldata balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes calldata userData
    ) external returns (uint256 bptOut, uint256[] memory amountsIn);
    function setPaused(bool paused) external;
    function setSwapFeePercentage(uint256 swapFeePercentage) external;
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function decimals() external pure returns (uint8);
    function getLargestSafeQueryWindow() external pure returns (uint256);
    function getTotalSamples() external pure returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function getActionId(bytes4 selector) external view returns (bytes32);
    function getAuthorizer() external view returns (address);
    function getInvariant() external view returns (uint256);
    function getLastInvariant() external view returns (uint256);
    function getLatest(uint8 variable) external view returns (uint256);
    function getMiscData()
        external
        view
        returns (
            int256 logInvariant,
            int256 logTotalSupply,
            uint256 oracleSampleCreationTimestamp,
            uint256 oracleIndex,
            bool oracleEnabled,
            uint256 swapFeePercentage
        );
    function getNormalizedWeights() external view returns (uint256[] memory);
    function getOwner() external view returns (address);
    function getPastAccumulators(OracleAccumulatorQuery[] calldata queries)
        external
        view
        returns (int256[] memory results);
    function getPausedState()
        external
        view
        returns (bool paused, uint256 pauseWindowEndTime, uint256 bufferPeriodEndTime);
    function getPoolId() external view returns (bytes32);
    function getRate() external view returns (uint256);
    function getSample(uint256 index)
        external
        view
        returns (
            int256 logPairPrice,
            int256 accLogPairPrice,
            int256 logBptPrice,
            int256 accLogBptPrice,
            int256 logInvariant,
            int256 accLogInvariant,
            uint256 timestamp
        );
    function getSwapFeePercentage() external view returns (uint256);
    function getTimeWeightedAverage(OracleAverageQuery[] calldata queries)
        external
        view
        returns (uint256[] memory results);
    function getVault() external view returns (address);
    function name() external view returns (string memory);
    function nonces(address owner) external view returns (uint256);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
}
