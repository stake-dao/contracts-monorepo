// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {MAVLocker} from "src/mav/locker/MAVLocker.sol";
import {MAVDepositor} from "src/mav/depositor/MAVDepositor.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {sdToken} from "src/base/token/sdToken.sol";

address constant MAV_BASE = 0x64b88c73A5DfA78D1713fE1b4c69a22d7E0faAa7;
address constant VE_MAV_BASE = 0xFcCB5263148fbF11d58433aF6FeeFF0Cc49E0EA5;
address constant SD_MAV_BASE = 0x75289388d50364c3013583d97bd70cED0e183e32;

address constant MAV_BNB = 0xd691d9a68C887BDF34DA8c36f63487333ACfD103;
address constant VE_MAV_BNB = 0xE6108f1869d37E5076a56168C66A1607EdB10819;
address constant SD_MAV_BNB = 0x75289388d50364c3013583d97bd70cED0e183e32;

abstract contract DeployMAVLLSidechain is Script, Test {
    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address private veToken;

    IERC20 private token;
    MAVLocker private locker;
    sdToken private sdMav;
    MAVDepositor private depositor;

    string private rpcAlias;

    constructor(address _token, address _veToken, address _sdMav, string memory _rpcAlias) {
        token = IERC20(_token);
        veToken = _veToken;
        sdMav = sdToken(_sdMav);
        rpcAlias = _rpcAlias;
    }

    function run() public {
        uint256 forkId = vm.createFork(vm.rpcUrl(rpcAlias));
        vm.selectFork(forkId);
        vm.startBroadcast(deployer);

        // deploy locker using salt
        locker = new MAVLocker(deployer, address(token), veToken);
        // deploy depositor
        depositor = new MAVDepositor(address(token), address(locker), address(sdMav), address(0));

        sdMav.setOperator(address(depositor));
        locker.setDepositor(address(depositor));

        if (locker.token() != address(token)) revert();
        if (locker.veToken() != address(veToken)) revert();
        if (locker.depositor() != address(depositor)) revert();
        if (locker.governance() != address(deployer)) revert();

        if (depositor.token() != address(token)) revert();
        if (depositor.locker() != address(locker)) revert();
        if (depositor.minter() != address(sdMav)) revert();
        if (depositor.governance() != address(deployer)) revert();
        if (depositor.gauge() != address(0)) revert();

        vm.stopBroadcast();
    }
}

contract DeployMAVLLBase is DeployMAVLLSidechain(MAV_BASE, VE_MAV_BASE, SD_MAV_BASE, "base") {}

contract DeployMAVLLBnb is DeployMAVLLSidechain(MAV_BNB, VE_MAV_BNB, SD_MAV_BNB, "bnb") {}
