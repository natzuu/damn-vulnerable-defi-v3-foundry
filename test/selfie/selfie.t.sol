// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "../../src/DamnValuableTokenSnapshot.sol";
import "../../src/selfie/SimpleGovernance.sol";
import "../../src/selfie/SelfiePool.sol";

contract SelfieTest is Test {
    address public deployer;
    address public player;

    DamnValuableTokenSnapshot public token;
    SimpleGovernance public governance;
    SelfiePool public pool;

    uint256 public constant TOKEN_INITIAL_SUPPLY = 2_000_000 ether;
    uint256 public constant TOKENS_IN_POOL = 1_500_000 ether;

    function setUp() public {
        deployer = makeAddr("deployer");
        player = makeAddr("player");

        vm.startPrank(deployer);
        token = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        governance = new SimpleGovernance(address(token));
        assertEq(governance.getActionCounter(), 1);

        pool = new SelfiePool(address(token), address(governance));
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));

        token.transfer(address(pool), TOKENS_IN_POOL);
        token.snapshot();
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
        vm.stopPrank();
    }

    function exploit() public {
        vm.startPrank(player);

        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();

        assertEq(token.balanceOf(player), TOKENS_IN_POOL);
        assertEq(token.balanceOf(address(pool)), 0);
    }
}
