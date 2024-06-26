// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {LibClone} from "solady/utils/LibClone.sol";
import {PENDLE} from "address-book/lockers/1.sol";
import {Pendle} from "address-book/protocols/1.sol";
import {DAO} from "address-book/dao/1.sol";

import {Constants} from "herdaddy/utils/Constants.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";
import {PendleVaultFactory} from "src/pendle/factory/PendleVaultFactory.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

interface PendleStrategy {
    function setVaultGaugeFactory(address _vaultGaugeFactory) external;
    function vaultGaugeFactory() external returns (address);
    function vaults(address) external view returns (bool);
    function sdGauges(address) external view returns (address);
}

interface PendleVault {
    function init(
        ERC20 _token,
        address _governance,
        string memory name_,
        string memory symbol_,
        PendleStrategy _pendleStrategy
    ) external;
    function deposit(address _staker, uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function withdrawAll() external;
    function governance() external view returns (address);
    function setGovernance(address _governance) external;
    function liquidityGauge() external view returns (address);
    function setLiquidityGauge(address _liquidityGauge) external;
    function setPendleStrategy(address _strategy) external;
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract PendleStrategyIntegrationTest is Test {
    PendleVaultFactory public factory;

    address public constant PENDLE_LPT_V3 = 0xBBd395D4820da5C89A3bCA4FA28Af97254a0FCBe; // CRVUSD
    address public constant PENDLE_LPT_OLD = 0xC9beCdbC62efb867cB52222b34c187fB170379C6; // CRVUSD

    address public constant PENDLE_DEPLOYER = 0x1FcCC097db89A86Bfc474A1028F93958295b1Fb7;

    ILiquidityGaugeStrat public gaugeImpl;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 19018738);
        vm.selectFork(forkId);

        gaugeImpl = ILiquidityGaugeStrat(deployBytecode(Constants.LGV4_BOOST_STRAT_0_2_BYTECODE, ""));

        // Deploying vault factory
        factory = new PendleVaultFactory(PENDLE.STRATEGY, DAO.STRATEGY_SDT_DISTRIBUTOR, address(gaugeImpl));

        // Setting new factory in strategy
        vm.prank(DAO.GOVERNANCE);
        PendleStrategy(PENDLE.STRATEGY).setVaultGaugeFactory(address(factory));
    }

    function testSetup() public {
        assertEq(factory.strategy(), PENDLE.STRATEGY);
        assertEq(factory.sdtDistributor(), DAO.STRATEGY_SDT_DISTRIBUTOR);
        assertEq(factory.vaultImpl(), 0x44A6A278A9a55fF22Fd5F7c6fe84af916396470C);
        assertNotEq(address(gaugeImpl), address(0));
        assertEq(factory.gaugeImpl(), address(gaugeImpl));
        assertEq(ILiquidityGaugeStrat(gaugeImpl).balanceOf(address(this)), 0);
        assertEq(factory.PENDLE_MARKET_FACTORY_V3(), 0x1A6fCc85557BC4fB7B534ed835a03EF056552D52);
        assertEq(factory.GOVERNANCE(), DAO.GOVERNANCE);
        assertEq(factory.PENDLE(), PENDLE.TOKEN);
        assertEq(factory.VESDT(), DAO.VESDT);
        assertEq(factory.SDT(), DAO.SDT);
        assertEq(factory.VEBOOST(), 0xD67bdBefF01Fc492f1864E61756E5FBB3f173506);

        assertEq(PendleStrategy(PENDLE.STRATEGY).vaultGaugeFactory(), address(factory));
    }

    // Testing cloning vault for an old LP (using old PendleMarketFactory)
    function testCloneVaultInvalidLP() public {
        vm.expectRevert(PendleVaultFactory.NOT_MARKET.selector);
        factory.cloneAndInit(PENDLE_LPT_OLD);

        vm.expectRevert(PendleVaultFactory.NOT_MARKET.selector);
        factory.cloneAndInit(address(0xBABA));
    }

    // Testing deploying vault for an existing LP
    function testCloneVault() public {
        // Events :
        // VaultDeployed
        // Vault.Initialized
        // GaugeDeployed
        // Approval
        // Vault.LiquidityGaugeSet(sdGauge)
        // Vault.GovernanceSet(GOVERNANCE)
        // Strategy.VaultToggled(vault, true)
        // Strategy.SdGaugeSet(lpToken, sdGauge)
        // Gauge.CommitOwnerShip(GOVERNANCE)

        vm.recordLogs();
        factory.cloneAndInit(PENDLE_LPT_V3);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 9);
        assertEq(entries[0].topics[0], keccak256("VaultDeployed(address,address,address)"));
        (address vault, address lptToken, address impl) = abi.decode(entries[0].data, (address, address, address));

        assertEq(entries[2].topics[0], keccak256("GaugeDeployed(address,address,address)"));
        (address gaugeProxy, address stakeToken, address gaugeImpl_) =
            abi.decode(entries[2].data, (address, address, address));

        assertEq(stakeToken, vault);
        assertEq(lptToken, PENDLE_LPT_V3);
        assertEq(impl, factory.vaultImpl());
        assertEq(gaugeImpl_, factory.gaugeImpl());

        string memory name = PendleVault(vault).name();
        string memory symbol = PendleVault(vault).symbol();

        assertEq(name, "Stake DAO LPT Silo crvUSD 27JUN2024 Vault");
        assertEq(symbol, "sdLPT Silo crvUSD 27JUN2024-vault");

        assertEq(PendleVault(vault).liquidityGauge(), gaugeProxy);
        assertEq(PendleVault(vault).governance(), DAO.GOVERNANCE);

        assertEq(PendleStrategy(PENDLE.STRATEGY).vaultGaugeFactory(), address(factory));
        assertEq(PendleStrategy(PENDLE.STRATEGY).vaultGaugeFactory(), address(factory));
        assertTrue(PendleStrategy(PENDLE.STRATEGY).vaults(vault));
        assertEq(PendleStrategy(PENDLE.STRATEGY).sdGauges(lptToken), gaugeProxy);

        // Cannot deploy two times the same one
        vm.expectRevert();
        factory.cloneAndInit(PENDLE_LPT_V3);
    }

    // Testing deposit & harvest (assert rewards boosted via locker)
    function testDepositAndWithdraw() public {
        address alice = address(0x1);

        vm.recordLogs();
        factory.cloneAndInit(PENDLE_LPT_V3);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        (address vault,,) = abi.decode(entries[0].data, (address, address, address));
        (address gaugeProxy,,) = abi.decode(entries[2].data, (address, address, address));

        // Give Alice some PENDLE_LPT_V3
        deal(PENDLE_LPT_V3, alice, 100e18);

        // Deposit 100 PENDLE_LPT_V3
        vm.startPrank(alice);
        ERC20(PENDLE_LPT_V3).approve(vault, 100e18);
        PendleVault(vault).deposit(alice, 100e18);
        vm.stopPrank();

        // Rewards in the locker
        assertEq(ERC20(PENDLE_LPT_V3).balanceOf(PENDLE.LOCKER), 100e18);
        assertEq(ERC20(PENDLE_LPT_V3).balanceOf(alice), 0);

        // Alice received gauge shares
        assertEq(ERC20(gaugeProxy).balanceOf(alice), 100e18);

        // Alice withdraws 50 PENDLE_LPT_V3
        vm.startPrank(alice);
        PendleVault(vault).withdraw(50e18);
        vm.stopPrank();

        // Rewards in the locker
        assertEq(ERC20(PENDLE_LPT_V3).balanceOf(PENDLE.LOCKER), 50e18);
        assertEq(ERC20(PENDLE_LPT_V3).balanceOf(alice), 50e18);

        // Alice loses half gauge shares
        assertEq(ERC20(gaugeProxy).balanceOf(alice), 50e18);
    }

    function deployBytecode(bytes memory bytecode, bytes memory args) internal returns (address deployed) {
        bytecode = abi.encodePacked(bytecode, args);
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DEPLOYMENT_FAILED");
    }
}
