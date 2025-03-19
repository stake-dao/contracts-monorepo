// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";

contract PreLaunchLockerHarness is PreLaunchLocker {
    constructor(address _token) PreLaunchLocker(_token) {}

    function _cheat_setState(STATE _state) external {
        _setState(_state);
    }

    function _cheat_balances(address account, uint256 amount) external {
        balances[account] = amount;
    }
}

contract ExtendedMockERC20 is MockERC20 {
    function _cheat_mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract GaugeMock {
    mapping(address => uint256) public balances;
    ExtendedMockERC20 private sdToken;

    constructor(ExtendedMockERC20 token) {
        sdToken = token;
    }

    function deposit(uint256 amount, address receiver) external {
        sdToken.transferFrom(msg.sender, address(this), amount);
        balances[receiver] += amount;
    }
}

contract DepositorMock {
    address public token;
    ExtendedMockERC20 private sdToken;
    GaugeMock private $gauge;

    constructor(address _token) {
        // set the expected token
        token = _token;

        // deploy the sdToken wrapper token
        sdToken = new ExtendedMockERC20();
        sdToken.initialize("StakeDAO Token", "sdTOKEN", 18);

        // deploy the gauge mock
        $gauge = new GaugeMock(sdToken);
    }

    function createLock(uint256 amount) external {
        // transfer the tokens from the sender to the contract
        ExtendedMockERC20(token).transferFrom(msg.sender, address(this), amount);

        // mint the sdToken to the locker
        sdToken._cheat_mint(msg.sender, amount);
    }

    function minter() external view returns (address) {
        return address(sdToken);
    }

    function gauge() external view returns (address) {
        return address($gauge);
    }
}
