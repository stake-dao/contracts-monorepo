// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DAO} from "@address-book/src/DaoEthereum.sol";
import {Script} from "forge-std/src/Script.sol";
import {SafeProxyFactoryLibrary} from "src/utils/SafeProxyFactoryLibrary.sol";
import {LockerPreLaunch} from "src/LockerPreLaunch.sol";
import {sdToken as SdToken} from "src/SDToken.sol";

/// @title PreLaunchDeploy
/// @notice This script is used to deploy the whole pre-launch protocol including:
///         the Locker, the sdToken, the Gauge and the LockerPreLaunch contract.
/// @dev How to use:
///      - Deploy using a Ledger signer: TOKEN=XXXX forge script PreLaunchDeploy --rpc-url https://XXXXX --ledger --broadcast
///      - Deploy locally on Anvil using one of the default accounts:
///         TOKEN=0x... forge script PreLaunchDeploy --rpc-url http://127.0.0.1:8545 \
///         --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
///         --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --broadcast
/// @custom:contact contact@stakedao.org
contract PreLaunchDeploy is Script {
    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS  & STATE VARIABLES
    ///////////////////////////////////////////////////////////////
    string internal constant DEFAULT_SD_TOKEN_PREFIX_NAME = "Stake DAO ";
    string internal constant DEFAULT_SD_TOKEN_PREFIX_SYMBOL = "sd";

    function _run(address token, string memory name, string memory symbol, uint256 customForceCancelDelay)
        internal
        returns (address sdToken, address gauge, address preLaunchLocker, address locker)
    {
        vm.startBroadcast();

        // 1. set the unique salt that will be used to deploy the locker
        uint256 salt = uint256(uint160(token));

        // 2. deploy the locker
        address[] memory _owners = new address[](1);
        _owners[0] = DAO.GOVERNANCE;
        locker = SafeProxyFactoryLibrary.deploy(salt, _owners);

        // 3. deploy the sdToken
        sdToken = address(new SdToken(name, symbol));

        // 4. deploy the gauge behind a proxy
        // TODO: We must deploy it once and store it in the address book.
        //       The implementation here is a slight variation of the original as this one
        //       allows null-address as distributor for the SDT token.
        address gaugeImplementation = deployCode("GaugeLiquidityV4.vy");
        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256("initialize(address,address,address,address,address,address)")),
            sdToken,
            DAO.GOVERNANCE,
            DAO.SDT,
            DAO.VESDT,
            DAO.VESDT_BOOST_PROXY,
            address(0) // distributor
        );
        gauge = address(new TransparentUpgradeableProxy(gaugeImplementation, DAO.PROXY_ADMIN, data));

        // 5. deploy the LockerPreLaunch and transfer the governance to the DAO
        preLaunchLocker = address(new LockerPreLaunch(token, sdToken, gauge, customForceCancelDelay));
        LockerPreLaunch(preLaunchLocker).transferGovernance(DAO.GOVERNANCE);

        // 6. set LockerPreLaunch as the sdToken operator
        SdToken(sdToken).setOperator(address(preLaunchLocker));

        vm.stopBroadcast();
    }

    function run() external returns (address sdToken, address gauge, address preLaunchLocker, address locker) {
        // @dev: Mandatory env variable that specify the address of the initial token.
        address token = vm.envAddress("TOKEN");

        // @dev: Optional env variables used to override the name and symbol of the deployed sdToken.
        //       If not provided, the name and symbol will be constructed by adding the StakeDAO prefixes
        //       to the name and symbol of the initial token.
        string memory name =
            vm.envOr("TOKEN_NAME", string.concat(DEFAULT_SD_TOKEN_PREFIX_NAME, IERC20Metadata(token).name()));
        string memory symbol =
            vm.envOr("TOKEN_SYMBOL", string.concat(DEFAULT_SD_TOKEN_PREFIX_SYMBOL, IERC20Metadata(token).symbol()));

        // @dev: Optional env variable used to override the force cancel delay.
        //       If not provided, the default value will be used.
        uint256 customForceCancelDelay = vm.envOr("FORCE_CANCEL_DELAY", uint256(0));

        (sdToken, gauge, preLaunchLocker, locker) = _run(token, name, symbol, customForceCancelDelay);
    }
}
