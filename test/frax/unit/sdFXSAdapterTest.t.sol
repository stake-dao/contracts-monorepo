// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import {FXS} from "address-book/lockers/1.sol";
import {sdFXSAdapter} from "src/frax/fxs/token/sdFXSAdapter.sol";
import {SendParam} from "LayerZero-v2/oft/interfaces/IOFT.sol";
import {MessagingFee} from "LayerZero-v2/oft/OFTCore.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

interface ILzEndpoint {
    function delegates(address _oapp) external view returns (address);
}

contract sdFXSAdapterTest is Test {
    sdFXSAdapter private tokenAdapter;
    ILzEndpoint private constant LZ_ENDPOINT = ILzEndpoint(0x1a44076050125825900e736c501f859c50fE728c);
    address private constant DELEGATE = address(0xABCD);
    address private constant USER = address(0xABAB);
    address private constant TOKEN = FXS.SDTOKEN;
    uint256 amountToSend = 1e18;
    uint32 dstEid = 30255; // fraxtal
    address private constant OFT_FRAXTAL = address(1);
    bytes32 dstPeer = bytes32(abi.encodePacked(OFT_FRAXTAL));

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        tokenAdapter = new sdFXSAdapter(TOKEN, address(LZ_ENDPOINT), DELEGATE);
        tokenAdapter.setPeer(30109, dstPeer);

        deal(TOKEN, USER, amountToSend);
        deal(USER, 1 ether);
    }

    function test_deploy() public {
        assertEq(tokenAdapter.token(), TOKEN);
        assertEq(address(tokenAdapter.endpoint()), address(LZ_ENDPOINT));
        assertEq(LZ_ENDPOINT.delegates(address(tokenAdapter)), DELEGATE);
        assertEq(tokenAdapter.owner(), address(this));
    }

    function test_delegate() public {
        address newDelegate = address(0xAABB);
        tokenAdapter.setDelegate(newDelegate);
        assertEq(LZ_ENDPOINT.delegates(address(tokenAdapter)), newDelegate);
    }

    function test_send() public {
        bytes32 recipientAddr = bytes32(abi.encodePacked(address(this)));
        address refundAddr = address(0xAABB);

        bytes memory options = bytes(hex"00030100110100000000000000000000000000030d40"); // 200k gas, 0 value

        SendParam memory params = SendParam(30109, recipientAddr, amountToSend, amountToSend, options, "", "");

        // calculate fee
        MessagingFee memory fees = tokenAdapter.quoteSend(params, false);

        vm.startPrank(USER);
        ERC20(TOKEN).approve(address(tokenAdapter), amountToSend);
        tokenAdapter.send{value: fees.nativeFee}(params, fees, refundAddr);
        vm.stopPrank();
    }
}
