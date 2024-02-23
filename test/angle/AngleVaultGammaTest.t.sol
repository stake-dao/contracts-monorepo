// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

// Base Tests
import "test/base/BaseTest.t.sol";

import {AngleVaultGamma} from "src/angle/vault/AngleVaultGamma.sol";
import {AngleMerklClaimer} from "src/angle/claimer/AngleMerklClaimer.sol";
import "src/base/external/TransparentUpgradeableProxy.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";
import {Angle} from "address-book/protocols/1.sol";
import {DAO} from "address-book/dao/1.sol";
import {IAngleMerkleDistributor} from "src/base/interfaces/IAngleMerkleDistributor.sol";
import {Constants} from "herdaddy/utils/Constants.sol";

contract AngleVaultGammaTest is BaseTest {
    address public constant BOB = address(0xB0B);
    address public constant ALICE = address(0xAA);
    address public constant LOCAL_DEPLOYER = address(0xDE);
    address public constant CLAIMER_USER = 0x5Be876Ed0a9655133226BE302ca6f5503E3DA569;
    address public constant GAMMA_AGEUR_ETH_LP = 0xE8f20fD90161de1d5B4cF7e2B5D92932CA06D5f4;
    address public constant GAMMA_AGEUR_USDC_LP = 0xF56Abca39c27D5C74F94c901b8C137fDf53B3E80;
    address public constant MERKLE_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    address public angle = Angle.ANGLE;

    uint256 public constant AMOUNT = 1e18;

    AngleVaultGamma public agEurEthVault;
    AngleVaultGamma public agEurUsdcVault;
    address public proxyAdmin = address(0xABCD);
    TransparentUpgradeableProxy public agEurEthGaugeProxy;
    TransparentUpgradeableProxy public agEurUsdcGaugeProxy;
    ILiquidityGaugeStrat public agEurEthGauge;
    ILiquidityGaugeStrat public agEurUsdcGauge;
    ILiquidityGaugeStrat public liquidityGaugeStratImpl;
    AngleMerklClaimer public claimer;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 17305960);
        vm.selectFork(forkId);

        vm.startPrank(LOCAL_DEPLOYER);

        // Deploy Vaults
        agEurEthVault =
            new AngleVaultGamma(GAMMA_AGEUR_ETH_LP, LOCAL_DEPLOYER, "stake dao AgEurEthGamma", "sdAgEurEthGamma");
        agEurUsdcVault =
            new AngleVaultGamma(GAMMA_AGEUR_USDC_LP, LOCAL_DEPLOYER, "stake dao AgEurUsdcGamma", "sdAgEurUsdcGamma");

        liquidityGaugeStratImpl = ILiquidityGaugeStrat(deployBytecode(Constants.LGV4_BOOST_STRAT_0_2_BYTECODE, ""));

        // Gauges
        // AgEur/Eth
        bytes memory AgEurEthGaugeData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address,string)",
            address(agEurEthVault),
            LOCAL_DEPLOYER,
            DAO.SDT,
            DAO.VESDT,
            DAO.VESDT_BOOST_PROXY,
            LOCAL_DEPLOYER,
            address(agEurEthVault),
            "agEur/ETH Gamma"
        );
        agEurEthGaugeProxy =
            new TransparentUpgradeableProxy(address(liquidityGaugeStratImpl), proxyAdmin, AgEurEthGaugeData);
        agEurEthGauge = ILiquidityGaugeStrat(address(agEurEthGaugeProxy));
        agEurEthVault.setLiquidityGauge(address(agEurEthGauge));

        // AgEur/Usdc
        bytes memory AgEurUsdcGaugeData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address,string)",
            address(agEurUsdcVault),
            LOCAL_DEPLOYER,
            DAO.SDT,
            DAO.VESDT,
            DAO.VESDT_BOOST_PROXY,
            LOCAL_DEPLOYER,
            address(agEurUsdcVault),
            "agEur/USDC Gamma"
        );
        agEurUsdcGaugeProxy =
            new TransparentUpgradeableProxy(address(liquidityGaugeStratImpl), proxyAdmin, AgEurUsdcGaugeData);
        agEurUsdcGauge = ILiquidityGaugeStrat(address(agEurUsdcGaugeProxy));
        agEurUsdcVault.setLiquidityGauge(address(agEurUsdcGauge));

        deal(GAMMA_AGEUR_ETH_LP, LOCAL_DEPLOYER, AMOUNT);
        deal(GAMMA_AGEUR_USDC_LP, LOCAL_DEPLOYER, AMOUNT);

        // Deploy Claimer
        claimer = new AngleMerklClaimer(LOCAL_DEPLOYER, LOCAL_DEPLOYER, LOCAL_DEPLOYER, LOCAL_DEPLOYER);

        // add ANGLE extra reward
        agEurEthGauge.add_reward(angle, address(claimer));
        agEurUsdcGauge.add_reward(angle, address(claimer));

        // whitelist the claimer to claim ANGLE via the merkle
        agEurEthVault.toggleOnlyOperatorCanClaim();
        agEurUsdcVault.toggleOnlyOperatorCanClaim();
        agEurEthVault.toggleOperator(address(claimer));
        agEurUsdcVault.toggleOperator(address(claimer));
        agEurEthVault.approveClaimer(angle, address(claimer));
        agEurUsdcVault.approveClaimer(angle, address(claimer));

        vm.startPrank(CLAIMER_USER);
        // Angle merkle distributor
        IAngleMerkleDistributor(MERKLE_DISTRIBUTOR).toggleOnlyOperatorCanClaim(CLAIMER_USER);
        IAngleMerkleDistributor(MERKLE_DISTRIBUTOR).toggleOperator(CLAIMER_USER, address(claimer));
        IERC20(angle).approve(address(claimer), type(uint256).max);
        vm.stopPrank();
    }

    function test01LGSettings() public {
        assertEq(agEurEthGauge.name(), "Stake DAO agEur/ETH Gamma Gauge");
        assertEq(agEurEthGauge.symbol(), "sdagEur/ETH Gamma-gauge");
    }

    function test02DepositToVault() public {
        vm.startPrank(LOCAL_DEPLOYER);
        IERC20(GAMMA_AGEUR_ETH_LP).approve(address(agEurEthVault), AMOUNT);
        agEurEthVault.deposit(LOCAL_DEPLOYER, AMOUNT);
        assertEq(IERC20(GAMMA_AGEUR_ETH_LP).balanceOf(address(agEurEthVault)), AMOUNT);
        assertEq(agEurEthGauge.balanceOf(LOCAL_DEPLOYER), AMOUNT);
    }

    function test03WithdrawFromVault() public {
        vm.startPrank(LOCAL_DEPLOYER);
        IERC20(GAMMA_AGEUR_USDC_LP).approve(address(agEurUsdcVault), AMOUNT);
        agEurUsdcVault.deposit(LOCAL_DEPLOYER, AMOUNT);
        agEurUsdcVault.withdraw(AMOUNT);
        vm.stopPrank();
        assertEq(IERC20(GAMMA_AGEUR_USDC_LP).balanceOf(address(agEurUsdcVault)), 0);
        assertEq(agEurUsdcGauge.balanceOf(LOCAL_DEPLOYER), 0);
    }

    function test04WithdrawRevert() public {
        vm.startPrank(LOCAL_DEPLOYER);
        IERC20(GAMMA_AGEUR_USDC_LP).approve(address(agEurUsdcVault), AMOUNT);
        agEurUsdcVault.deposit(ALICE, AMOUNT);
        vm.expectRevert(0xb1a6e9be); // NOT_ENOUGH_STAKED()
        agEurUsdcVault.withdraw(AMOUNT);
        vm.stopPrank();
        vm.prank(ALICE);
        agEurUsdcVault.withdraw(AMOUNT);
        assertEq(IERC20(GAMMA_AGEUR_USDC_LP).balanceOf(address(agEurUsdcVault)), 0);
        assertEq(agEurUsdcGauge.balanceOf(LOCAL_DEPLOYER), 0);
    }

    // function test05ClaimAndNotifyReward() public {
    //     bytes32[][] memory proofs = new bytes32[][](1);
    //     proofs[0] = new bytes32[](8);
    //     proofs[0][0] = bytes32(0x7a4659e72dfaf8a9f3d7503d67f61b46b246903abde724b3d9c9b3256ee319eb);
    //     proofs[0][1] = bytes32(0x7ad53b3544ed045ce681b2f68a4ed172da8c9aba26c53d51c816d220ccf20c0b);
    //     proofs[0][2] = bytes32(0x4269069e07f148dd79acaf4e38b0ff83676ed2382954fc96ffea716691500f46);
    //     proofs[0][3] = bytes32(0x0402e84c73bc4cef6df7daedc6e74453e1908f0f54c19dee694e05febc65969d);
    //     proofs[0][4] = bytes32(0x56c650aa62bf9432161dbd07cd1d4d8c8ebf847ea64678cca3e0dc70485db7e9);
    //     proofs[0][5] = bytes32(0x9f90a863073ff9c53724f2db726e8b377f775573d95d343ba3ff6ae24c54eaf1);
    //     proofs[0][6] = bytes32(0x61e662533a3bcbd97485576669e9b5d6900eb7cfad4a5b30a997a64eb1a74b72);
    //     proofs[0][7] = bytes32(0x7cd0579c204c2f58c729a5b38f96b5eff8e83439bf3b4f7769891a39274ed864);
    //     vm.prank(LOCAL_DEPLOYER);
    //     claimer.claimAndNotify(proofs, CLAIMER_USER, 2184207418023393600000000);
    //     uint256 userBalance = IERC20(AddressBook.ANGLE).balanceOf(CLAIMER_USER);
    //     assertEq(userBalance, 0);
    //     uint256 claimerBalance = IERC20(AddressBook.ANGLE).balanceOf(address(claimer));
    // }
}
