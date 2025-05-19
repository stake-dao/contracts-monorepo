// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {DAO} from "address-book/src/DAOEthereum.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {BaseTest} from "test/BaseTest.t.sol";

abstract contract DepositorTest is BaseTest {
    address internal depositor;
    address internal governance;

    // etched addresses
    address internal token;
    address internal veToken;
    address internal gauge;

    // mock addresses
    address internal locker;
    address internal minter;

    constructor(address _token, address _veToken, address _gauge) {
        // set the governance
        governance = DAO.GOVERNANCE;

        // deploy the protocol token at the address of the expected protocol token
        MockERC20 mockToken = new MockERC20();
        mockToken.initialize("Token Name", "TKN", 18);
        vm.etch(_token, address(mockToken).code);
        token = _token;

        // deploy the reward token at the address of the expected reward token
        MockVeToken mockVeToken = new MockVeToken();
        vm.etch(_veToken, address(mockVeToken).code);
        veToken = _veToken;

        // deploy gauge mock at the address of the expected gauge
        MockLiquidityGauge mockGauge = new MockLiquidityGauge();
        vm.etch(_gauge, address(mockGauge).code);
        gauge = _gauge;

        // deploy locker, accountant and fee receiver mocks
        locker = address(new MockLocker());

        // deploy minter mock
        MockERC20 minterMock = new MockERC20();
        minterMock.initialize("Minter Token", "MT", 18);
        minter = address(minterMock);

        // label the important addresses
        vm.label(token, "Token");
        vm.label(veToken, "veToken");
        vm.label(gauge, "Gauge");
        vm.label(locker, "Locker");
        vm.label(governance, "Governance");
        vm.label(depositor, "Depositor");
    }

    function setUp() public virtual {
        // deploy the accumulator
        depositor = _deployDepositor();
    }

    // @dev must be implemented by the test contract
    function _deployDepositor() internal virtual returns (address) {}
}

contract MockLiquidityGauge {
    function deposit_reward_token(address token, uint256 amount) external {
        MockERC20(token).transferFrom(msg.sender, address(this), amount);
    }
}

contract MockVeToken {
    function increase_unlock_time(uint256 unlockTime) external {}
    function increase_amount(uint256 amount) external {}
    function locked__end(address locker) external view returns (uint256) {}

    // yearn
    function modify_lock(uint256 amount, uint256 unlockTime) external {}

    // pendle
    function increaseLockPosition(uint128 additionalAmountToLock, uint128 newExpiry)
        external
        returns (uint128 newVeBalance)
    {}
    function positionData(address) external view returns (uint128 amount, uint128 expiry) {}
}

contract MockLocker {
    function execTransactionFromModuleReturnData(address target, uint256 value, bytes memory data, uint8)
        external
        returns (bool success, bytes memory returnData)
    {
        (success, returnData) = target.call{value: value}(data);
        return (success, returnData);
    }
}
