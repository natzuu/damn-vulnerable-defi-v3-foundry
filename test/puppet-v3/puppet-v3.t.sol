// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract PuppetV3Test is Test {
    address public deployer;
    address public player;

    function setUp() public {
        deployer = makeAddr("deployer");
        player = makeAddr("player");

        vm.startPrank(deployer);

        vm.stopPrank();
    }

    function exploit() public {
        vm.startPrank(player);

        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();
    }
}
