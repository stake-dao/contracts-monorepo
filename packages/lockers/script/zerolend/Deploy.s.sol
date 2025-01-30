// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";

import "script/common/DeployAccumulator.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {sdToken as SdToken} from "src/common/token/sdToken.sol";
import {Accumulator} from "src/linea/zerolend/Accumulator.sol";
import {Locker} from "src/linea/zerolend/Locker.sol";
import {Depositor} from "src/linea/zerolend/Depositor.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {IDepositor} from "src/common/interfaces/IDepositor.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";

// TODO create, import and use linea governance addresses
library DAO {
    address public constant MAIN_DEPLOYER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    address public constant TREASURY = address(2);
    address public constant LIQUIDITY_FEES_RECIPIENT = address(3);
    address public constant GOVERNANCE = address(4);
}

contract Deploy is DeployAccumulator {
    address sdZero;
    address liquidityGauge;
    address locker;
    address depositor;

    address zeroLockerToken = 0x08D5FEA625B1dBf9Bae0b97437303a0374ee02F8; // NFT token contract.
    address zeroToken = 0x78354f8DcCB269a615A7e0a24f9B0718FDC3C7A7;
    address veZero = 0xf374229a18ff691406f99CCBD93e8a3f16B68888;

    function run() public {
        vm.createSelectFork("linea");
        _run(DAO.MAIN_DEPLOYER, DAO.TREASURY, DAO.LIQUIDITY_FEES_RECIPIENT, DAO.GOVERNANCE);
    }

    function _beforeDeploy() internal virtual override {
        // Deploy locker.
        locker = address(new Locker(zeroLockerToken, DAO.MAIN_DEPLOYER, zeroToken, veZero));

        // Deploy sdZero.
        // TODO confirm name & symbol
        sdZero = address((new SdToken("Stake DAO ZeroLend", "sdZERO")));

        // Deploy gauge.
        // TODO confirm that can't deploy as proxy because LiquidityGaugeV4XChain doesn't have a initialize function
        liquidityGauge = deployCode("vyper/LiquidityGaugeV4XChain.vy", abi.encode(sdZero, DAO.MAIN_DEPLOYER));

        // Deploy depositor.
        depositor = address(new Depositor(address(zeroToken), locker, sdZero, address(liquidityGauge)));
    }

    function _deployAccumulator() internal override returns (address payable) {
        require(sdZero != address(0));
        require(liquidityGauge != address(0));
        require(locker != address(0));

        return payable(new Accumulator(liquidityGauge, locker, DAO.MAIN_DEPLOYER));
    }

    function _afterDeploy() internal virtual override {
        // Setup access rights and rewards.
        ISdToken(sdZero).setOperator(address(depositor));

        ILocker(locker).setDepositor(address(depositor));
        ILocker(locker).setAccumulator(address(accumulator));

        ILiquidityGauge(liquidityGauge).add_reward(address(zeroToken), address(accumulator));
        // Planned for future ZeroLend protocol upgrade.
        // liquidityGauge.add_reward(address(WETH), address(accumulator));

        // Transfer all governance to DAO for following contracts.
        //  - sdZero only has an operator which was set to the depositor
        //  - gauge (need to call accept_transfer_ownership() from DAO.GOVERNANCE)
        //  - depositor (need to call acceptGovernance() from DAO.GOVERNANCE)
        //  - locker (need to call acceptGovernance() from DAO.GOVERNANCE)
        //  - accumulator is already taken care of in DeployAccumulator
        ILiquidityGauge(liquidityGauge).commit_transfer_ownership(DAO.GOVERNANCE);
        IDepositor(depositor).transferGovernance(DAO.GOVERNANCE);
        ILocker(locker).transferGovernance(DAO.GOVERNANCE);
    }
}
