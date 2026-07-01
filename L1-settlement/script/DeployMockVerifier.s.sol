// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {MockVerifier} from "../test/mock/MockVerifier.sol";

/// @notice Deploys a MockVerifier and configures it to accept-always, for
/// local mock-mode testnets where no real SP1 proof is ever produced. Never
/// use this in a network that carries any real value.
contract DeployMockVerifier is Script {
    function run() public returns (address verifier) {
        vm.startBroadcast();

        console.log("Deploying MockVerifier (accept-always)...");
        MockVerifier mockVerifier = new MockVerifier();
        mockVerifier.mockVerifyProof(true);
        verifier = address(mockVerifier);

        console.log("MockVerifier deployed at:", verifier);

        vm.stopBroadcast();
    }
}
