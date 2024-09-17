// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import "address-book/src/dao/42161.sol";
import "address-book/src/lockers/42161.sol";

import "murky/Merkle.sol";
import "src/arbitrum/cake/IFO.sol";

contract IFOTest is Test {
    IFO public ifo;
    IFOFactory public ifoFactory;

    uint256 public constant BLOCK_NUMBER = 253_008_401;
    address public constant LOCKER = 0x1E6F87A9ddF744aF31157d8DaA1e3025648d042d;
    address public constant CAKE_IFO = 0x6164B999597a6F30DA9aEF8A7F31D6dD7AE57e04;

    /// Users
    address public constant USER_1 = address(0x1);
    address public constant USER_2 = address(0x2);

    bytes32[] private hashes;
    bytes32 private merkleRoot;

    Merkle private merkle;
    bytes32[] private user1Proof;
    bytes32[] private user2Proof;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum"), BLOCK_NUMBER);

        ifoFactory = new IFOFactory(CAKE.EXECUTOR, address(this), address(this));
        ifoFactory.createIFO(CAKE_IFO);
        ifo = IFO(ifoFactory.ifos(CAKE_IFO));

        vm.prank(DAO.MAIN_DEPLOYER);
        IExecutor(CAKE.EXECUTOR).allowAddress(address(ifoFactory));

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

        ifoFactory.setMerkleRoot(address(ifo), merkleRoot, 300e18);

        deal(address(ifo.dToken()), USER_1, 100e18);
        deal(address(ifo.oToken()), USER_2, 200e18);
    }

    function test_initialSetup() public view {
        assertEq(ifoFactory.ifos(CAKE_IFO), address(ifo));
        assertEq(address(ifo.locker()), CAKE.EXECUTOR);
        assertEq(address(ifo.ifoFactory()), address(ifoFactory));
        assertEq(address(ifo.cakeIFO()), CAKE_IFO);
        assertEq(address(ifo.dToken()), ICakeIFOV8(CAKE_IFO).addresses(0));
        assertEq(address(ifo.oToken()), ICakeIFOV8(CAKE_IFO).addresses(1));

        assertEq(ifo.merkleRoot(), merkleRoot);
        assertEq(ifo.sdCakeGaugeTotalSupply(), 300e18);
    }

    function test_deposit_private_sale() public {
        uint256 startTimestamp = ifo.firstPeriodStart();
        vm.warp(startTimestamp + 1);

        uint8 pid = 1;
        uint256 amountToDeposit = 10e18;

        _depositPoolFirstPeriod(USER_1, amountToDeposit, pid, 0, 100e18, user1Proof);

        assertEq(ifo.depositors(USER_1, pid), amountToDeposit);
        assertEq(ifo.totalDeposits(pid), amountToDeposit);
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
        address pancakeProfile = ICakeIFOV8(CAKE_IFO).addresses(2);

        address iCAKEV3 = ICakeIFOV8(CAKE_IFO).addresses(3);
        uint credit = ICakeV3(iCAKEV3).getUserCredit(LOCKER);

        vm.mockCall(
            pancakeProfile,
            abi.encodeWithSignature("getUserStatus(address)", CAKE.EXECUTOR),
            abi.encode(true)
        );

        vm.mockCall(
            iCAKEV3,
            abi.encodeWithSignature("getUserCredit(address)", CAKE.EXECUTOR),
            abi.encode(credit)
        );

        vm.startPrank(_user);
        ERC20(address(ifo.dToken())).approve(address(ifo), _amount);
        // pid 1
        ifo.depositPoolFirstPeriod(_amount, _pid, _merkleIndex, _gAmount, _merkleProof);
        vm.stopPrank();
    }

    function _depositPoolSecondPeriod(address _user, uint256 _amount, uint8 _pid) internal {
        vm.startPrank(_user);
        ERC20(address(ifo.dToken())).approve(address(ifo), _amount);
        ifo.depositPoolSecondPeriod(_amount, _pid);
        vm.stopPrank();
    }

    function endTimestamp() external view returns (uint256) {
        return ICakeIFOV8(CAKE_IFO).endTimestamp();
    }
}
