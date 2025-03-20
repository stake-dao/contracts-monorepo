// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";
import {Test} from "forge-std/src/Test.sol";
import {sdToken as SdToken} from "src/common/token/sdToken.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";

contract PreLaunchLockerTest is Test {
    address internal token;
    SdToken internal sdToken;
    ILiquidityGauge internal gauge;

    PreLaunchLocker locker;

    function setUp() public {
        token = makeAddr("token");
        sdToken = new SdToken("sdToken", "sdTOKEN");
        gauge = ILiquidityGauge(address(new GaugeMock(address(sdToken))));

        locker = new PreLaunchLocker(token, address(sdToken), address(gauge));
    }
}

contract GaugeMock {
    // mapping(address => uint256) public balances;
    address private sdToken;

    constructor(address token) {
        sdToken = token;
    }

    function deposit(uint256 amount, address receiver) external {
        SdToken(sdToken).transferFrom(msg.sender, address(this), amount);
        // balances[receiver] += amount;
    }

    function lp_token() external view returns (address) {
        return sdToken;
    }
}

contract ExtendedMockERC20 is MockERC20 {
    function _cheat_mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
