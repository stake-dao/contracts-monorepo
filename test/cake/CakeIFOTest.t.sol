// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ICakeDepositor} from "src/base/interfaces/ICakeDepositor.sol";
import {ICakeLocker} from "src/base/interfaces/ICakeLocker.sol";
import {ICakeV3} from "src/base/interfaces/ICakeV3.sol";
import {Executor} from "src/base/utils/Executor.sol";
import "src/cake/ifo/CakeIFOFactory.sol";

import {CAKE} from "address-book/lockers/56.sol";
import {DAO} from "address-book/dao/56.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC721} from "solady/src/tokens/ERC721.sol";
import {Merkle} from "murky/Merkle.sol";

interface ICakeProfile {
    function createProfile(uint256 teamId, address nftAddress, uint256 tokenId) external;
}

interface IBunnyFactory {
    function mintNFT(uint8 bunnyId) external;
}

interface ICakeWhitelist {
    function addAddressToWhitelist(address _addr) external;
}

contract CakeIFOTest is Test {
    CakeIFOFactory private factory;
    Executor private executor;
    ICakeLocker private constant LOCKER = ICakeLocker(CAKE.LOCKER);
    ICakeDepositor private constant DEPOSITOR = ICakeDepositor(CAKE.DEPOSITOR);

    ICakeIFOV7 private constant CAKE_IFO = ICakeIFOV7(0x5f77A54F4314aef5BDd311aCfcccAC90B39432e8);
    address private constant CAKE_BUNNY = 0xDf7952B35f24aCF7fC0487D01c8d5690a60DBa07;
    address private constant CAKE_BUNNY_FACTORY = 0xfa249Caa1D16f75fa159F7DFBAc0cC5EaB48CeFf;
    address private constant CAKE_PROFILE = 0xDf4dBf6536201370F95e06A0F8a7a70fE40E388a;
    // pid 0 private sale
    // pid 1 public/base sale
    CakeIFO private ifo;

    ERC20 private dToken;
    ERC20 private oToken;

    address private constant USER_1 = address(0xABCD);
    address private constant USER_2 = address(0xABBB);
    address private constant FEE_RECEIVER = address(0xFEEE);
    address private constant GOVERNANCE = DAO.GOVERNANCE;

    bytes32[] private hashes;
    bytes32 private merkleRoot;

    Merkle private merkle;
    bytes32[] private user1Proof;
    bytes32[] private user2Proof;

    function setUp() external {
        uint256 forkId = vm.createFork(vm.rpcUrl("bnb"), 34_949_400);
        vm.selectFork(forkId);

        // deploy the executor and set it because it has deployed after fork time
        executor = new Executor(GOVERNANCE);

        factory = new CakeIFOFactory(address(LOCKER), address(executor), address(this), FEE_RECEIVER);

        // allow the factory to call the executeTo on the executor
        vm.startPrank(GOVERNANCE);
        executor.allowAddress(address(factory));
        LOCKER.transferGovernance(address(executor));
        executor.execute(address(LOCKER), 0, abi.encodeWithSignature("acceptGovernance()", ""));
        vm.stopPrank();

        // create new ifo
        factory.createIFO(address(CAKE_IFO));
        ifo = CakeIFO(factory.ifos(address(CAKE_IFO)));
        dToken = ERC20(ifo.dToken());
        oToken = ERC20(ifo.oToken());

        // Create Merkle
        merkle = new Merkle();
        bytes32[] memory datas = new bytes32[](2);
        datas[0] = keccak256(abi.encodePacked(uint256(0), USER_1, uint256(100e18)));
        datas[1] = keccak256(abi.encodePacked(uint256(1), USER_2, uint256(200e18)));
        merkleRoot = merkle.getRoot(datas);
        user1Proof = merkle.getProof(datas, 0);
        user2Proof = merkle.getProof(datas, 1);
        merkle.verifyProof(merkleRoot, user1Proof, datas[0]);
        merkle.verifyProof(merkleRoot, user2Proof, datas[0]);
        factory.setMerkleRoot(address(ifo), merkleRoot, 300e18);

        deal(address(dToken), USER_1, 1_000_000e18);
        deal(CAKE.TOKEN, address(LOCKER), 100e18);
        deal(address(dToken), USER_2, 1000e18);
        deal(CAKE.GAUGE, USER_1, 100e18);

        // create locker profile
        // mint Bunny NFT
        vm.startPrank(address(LOCKER));
        ERC20(CAKE.TOKEN).approve(CAKE_BUNNY_FACTORY, 100e18);
        vm.recordLogs();
        IBunnyFactory(CAKE_BUNNY_FACTORY).mintNFT(8);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 4);
        uint256 tokenId = uint256(entries[3].topics[2]);
        // create profile
        ERC721(CAKE_BUNNY).approve(CAKE_PROFILE, tokenId);
        ERC20(CAKE.TOKEN).approve(CAKE_PROFILE, 100e18);
        ICakeProfile(CAKE_PROFILE).createProfile(1, CAKE_BUNNY, tokenId);
        vm.stopPrank();
    }

    function test_factory_creation() external {
        assertEq(factory.locker(), address(LOCKER));
        assertEq(address(factory.executor()), address(executor));
    }

    function test_ifo_creation() external {
        assertEq(address(ifo.cakeIFO()), address(CAKE_IFO));
        assertEq(address(ifo.executor()), address(executor));
        assertEq(address(dToken), CAKE_IFO.lpToken());
        assertEq(address(oToken), CAKE_IFO.offeringToken());
        assertEq(ifo.locker(), address(LOCKER));

        // check period
        uint256 firstPeriodEnd = ifo.firstPeriodEnd();
        assertEq(firstPeriodEnd - ifo.firstPeriodStart(), CAKE_IFO.endTimestamp() - firstPeriodEnd);
    }

    function test_deposit_first_period() external {
        uint8 pid = 1;
        uint256 amountToDeposit = 10e18;

        _depositPoolFirstPeriod(USER_1, amountToDeposit, pid, 0, 100e18, user1Proof);
        _depositPoolFirstPeriod(USER_2, amountToDeposit, pid, 1, 200e18, user2Proof);

        assertEq(ifo.depositors(USER_1, 1), amountToDeposit);
        assertEq(ifo.depositors(USER_2, 1), amountToDeposit);
        assertEq(ifo.totalDeposits(1), amountToDeposit * 2);
        assertEq(ifo.userTotalDeposits(USER_1), amountToDeposit);
        assertEq(ifo.userTotalDeposits(USER_2), amountToDeposit);
    }

    function test_deposit_first_period_private_sale() external {
        uint8 pid = 0;
        uint256 amountToDeposit = 20e18;

        // whitelist locker (action required by pancake)
        vm.prank(0xeCc90d54B10ADd1ab746ABE7E83abe178B72aa9E);
        ICakeWhitelist(address(CAKE_IFO)).addAddressToWhitelist(address(LOCKER));

        // lp limit
        (,, uint256 lpLimit,,,,) = CAKE_IFO.viewPoolInformation(pid);
        uint256 dTokenDepositable = lpLimit * 1e18 / 300e18 * 100e18 / 1e18;

        _depositPoolFirstPeriod(USER_1, dTokenDepositable, pid, 0, 100e18, user1Proof);
    }

    function test_deposit_first_period_increase_dToken_depositable() external {
        uint8 pid = 1;
        uint256 amountToDeposit = 10e18;

        // no lp limit for pid = 1
        uint256 lockerCredit =
            ICakeV3(CAKE_IFO.iCakeAddress()).getUserCreditWithIfoAddr(address(LOCKER), address(CAKE_IFO));
        uint256 dTokenDepositable = lockerCredit * 1e18 / 300e18 * 100e18 / 1e18;

        // deposit max depositable
        _depositPoolFirstPeriod(USER_1, dTokenDepositable, pid, 0, 100e18, user1Proof);

        // USER 1
        vm.startPrank(USER_1);
        dToken.approve(address(ifo), 1);
        // pid 1
        vm.expectRevert(CakeIFO.AboveMax.selector);
        ifo.depositPoolFirstPeriod(1, pid, 0, 100e18, user1Proof);

        // deposit cake on locker to increase dToken depositable
        dToken.approve(address(DEPOSITOR), 1000e18);
        DEPOSITOR.deposit(1000e18, true, true, USER_1);

        // deposit again
        ifo.depositPoolFirstPeriod(1, pid, 0, 100e18, user1Proof);

        vm.stopPrank();
    }

    function test_deposit_second_period_no_fees() external {
        uint8 pid = 1;
        uint256 amountToDeposit = 10e18;

        skip(1 hours);

        uint256 snapshotCakeIFO = dToken.balanceOf(address(CAKE_IFO));

        vm.startPrank(USER_1);
        dToken.approve(address(ifo), amountToDeposit);
        ifo.depositPoolSecondPeriod(amountToDeposit, pid);
        vm.stopPrank();

        assertEq(ifo.depositors(USER_1, pid), amountToDeposit);
        assertEq(dToken.balanceOf(address(ifo)), 0);
        assertEq(dToken.balanceOf(address(CAKE_IFO)) - snapshotCakeIFO, amountToDeposit);
    }

    function test_deposit_second_period_fee() external {
        address feeReceiver = address(0xABFF);
        // set protocol fees
        factory.updateProtocolFee(1_500); // 15%
        factory.setFeeReceiver(feeReceiver);

        uint8 pid = 1;
        uint256 amountToDeposit = 10e18;

        skip(1 hours);

        uint256 snapshotCakeIFO = dToken.balanceOf(address(CAKE_IFO));

        _depositPoolSecondPeriod(USER_1, amountToDeposit, pid);

        uint256 feeCharged = amountToDeposit * factory.protocolFeesPercent() / factory.DENOMINATOR();
        assertEq(ifo.depositors(USER_1, pid), amountToDeposit - feeCharged);
        assertEq(dToken.balanceOf(address(ifo)), 0);
        assertEq(dToken.balanceOf(address(CAKE_IFO)) - snapshotCakeIFO, amountToDeposit - feeCharged);
        assertEq(dToken.balanceOf(feeReceiver), feeCharged);
    }

    function test_deposit_second_period_revert() external {
        uint8 pid = 1;
        uint256 amountToDeposit = 10e18;

        vm.prank(USER_1);
        vm.expectRevert(CakeIFO.NotInSecondPeriod.selector);
        ifo.depositPoolSecondPeriod(amountToDeposit, pid);
    }

    function test_harvest_pool() external {
        uint256 amountToDeposit = 10e18;
        uint8 pid = 1;
        _depositPoolFirstPeriod(USER_1, amountToDeposit, pid, 0, 100e18, user1Proof);

        skip(4 hours);

        uint256 snapshotDToken = oToken.balanceOf(address(ifo));
        uint256 snapshotOToken = dToken.balanceOf(address(ifo));

        ifo.harvestPool(1);

        uint256 reward = oToken.balanceOf(address(ifo)) - snapshotDToken;
        uint256 refund = dToken.balanceOf(address(ifo)) - snapshotOToken;

        (uint256 vestingPercentage,,,) = CAKE_IFO.viewPoolVestingInformation(pid);
        assertEq(vestingPercentage, 100);
        assertEq(reward, 0); // no initial oToken reward, all in vesting
        assertGt(refund, 0);

        assertEq(ifo.rewardRate(pid), 0);
        assertEq(ifo.refundRate(pid), refund * 1e18 / amountToDeposit);
    }

    function test_release() external {
        uint256 amountToDeposit1 = 10e18;
        uint256 amountToDeposit2 = 20e18;
        uint8 pid = 1;

        _depositPoolFirstPeriod(USER_1, amountToDeposit1, pid, 0, 100e18, user1Proof);
        _depositPoolFirstPeriod(USER_2, amountToDeposit2, pid, 1, 200e18, user2Proof);

        skip(4 hours);

        ifo.harvestPool(1);

        // vesting cliff time
        skip(1 weeks);

        assertLt(CAKE_IFO.vestingStartTime(), block.timestamp);
        uint256 snapshotDToken = dToken.balanceOf(address(ifo));
        uint256 snapshotOToken = oToken.balanceOf(address(ifo));

        assertEq(ifo.rewardRate(pid), 0);

        // first release
        ifo.release(pid);

        uint256 rewardReleased = oToken.balanceOf(address(ifo)) - snapshotOToken;
        uint256 refundReleased = dToken.balanceOf(address(ifo)) - snapshotDToken;
        assertEq(refundReleased, 0); // no refund to release during vesting time
        assertGt(rewardReleased, 0);

        uint256 rewardRate = ifo.rewardRate(pid);
        assertEq(rewardRate, rewardReleased * 1e18 / (amountToDeposit1 + amountToDeposit2));

        skip(1 hours);
        // second release
        ifo.release(pid);
        assertGt(ifo.rewardRate(pid), rewardRate);
    }

    function test_claim() external {
        uint256 amountToDeposit1 = 10e18;
        uint256 amountToDeposit2 = 20e18;
        uint8 pid = 1;

        _depositPoolFirstPeriod(USER_1, amountToDeposit1, pid, 0, 100e18, user1Proof);
        _depositPoolFirstPeriod(USER_2, amountToDeposit2, pid, 1, 200e18, user2Proof);

        skip(4 hours);

        ifo.harvestPool(1);

        // vesting cliff time
        skip(1 weeks);

        assertEq(ifo.rewardRate(pid), 0);

        ifo.release(pid);

        vm.prank(USER_1);
        ifo.claim(pid, false);
        vm.prank(USER_2);
        ifo.claim(pid, false);

        assertEq(oToken.balanceOf(address(ifo)), 0);
        assertEq(oToken.balanceOf(USER_1) * 2, oToken.balanceOf(USER_2));
    }

    function _depositPoolFirstPeriod(
        address _user,
        uint256 _amount,
        uint8 _pid,
        uint256 _merkleIndex,
        uint256 _gAmount,
        bytes32[] memory _merkleProof
    ) internal {
        // USER 1
        vm.startPrank(_user);
        dToken.approve(address(ifo), _amount);
        // pid 1
        ifo.depositPoolFirstPeriod(_amount, _pid, _merkleIndex, _gAmount, _merkleProof);
        vm.stopPrank();
    }

    function _depositPoolSecondPeriod(address _user, uint256 _amount, uint8 _pid) internal {
        vm.startPrank(_user);
        dToken.approve(address(ifo), _amount);
        ifo.depositPoolSecondPeriod(_amount, _pid);
        vm.stopPrank();
    }
}
