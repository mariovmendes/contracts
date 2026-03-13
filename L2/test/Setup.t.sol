// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { Mailbox } from "@ssv/src/core/Mailbox.sol";
import { PingPong } from "@ssv/src/core/PingPong.sol";
import { BridgeableToken } from "@ssv/src/core/BridgeableToken.sol";
import { Bridge } from "@ssv/src/core/Bridge.sol";
import { StagedMailbox } from "@ssv/src/core/StagedMailbox.sol";

contract Setup is Test {
    Mailbox public mailbox;
    PingPong public pingPong;
    BridgeableToken public myToken;
    Bridge public bridge;
    StagedMailbox public stagedMailbox;

    address public immutable DEPLOYER = makeAddr("Deployer");
    address public immutable COORDINATOR = makeAddr("Coordinator");

    uint256 public constant INITIAL_ETH_BALANCE = 10 ether;

    function setUp() public {
        vm.label(DEPLOYER, "Deployer");
        vm.label(COORDINATOR, "Coordinator");

        vm.deal(DEPLOYER, INITIAL_ETH_BALANCE);
        vm.deal(COORDINATOR, INITIAL_ETH_BALANCE);

        vm.prank(DEPLOYER);
        mailbox = new Mailbox(address(COORDINATOR));
        pingPong = new PingPong(address(mailbox));
        bridge = new Bridge(address(mailbox), address(COORDINATOR));
        myToken = new BridgeableToken(address(bridge));
        stagedMailbox = new StagedMailbox(address(COORDINATOR));

        vm.label(address(mailbox), "Mailbox");
        vm.label(address(pingPong), "PingPong");
        vm.label(address(myToken), "MyToken");
        vm.label(address(bridge), "Bridge");
        vm.label(address(stagedMailbox), "StagedMailbox");
    }
}
