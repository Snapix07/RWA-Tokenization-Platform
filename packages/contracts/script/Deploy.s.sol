// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {Counter} from "../src/Counter.sol";

contract Deploy is Script {
    string constant SALT_VERSION = "v1";

    function run() external returns (Counter counter) {
        bytes32 salt = keccak256(abi.encodePacked("rwa-platform.Counter.", SALT_VERSION));

        vm.startBroadcast();
        counter = new Counter{salt: salt}();
        vm.stopBroadcast();

        console2.log("Counter deployed at:", address(counter));
    }
}
