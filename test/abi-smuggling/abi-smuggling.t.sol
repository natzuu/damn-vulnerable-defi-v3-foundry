// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {SelfAuthorizedVault} from "../../src/abi-smuggling/SelfAuthorizedVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AbiSmugglingTest is Test {
    address public deployer;
    address public player;
    address public recovery;

    DamnValuableToken public token;
    SelfAuthorizedVault public vault;

    uint256 public constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    function setUp() public {
        deployer = makeAddr("deployer");
        player = makeAddr("player");
        recovery = makeAddr("recovery");

        vm.startPrank(deployer);

        // deploy the dvt contract
        token = new DamnValuableToken();

        // deploy vault
        vault = new SelfAuthorizedVault();
        assertTrue(vault.getLastWithdrawalTimestamp() != 0);

        // set permissions
        bytes32 deployerPermission = vault.getActionId(0x85fb709d, deployer, address(vault));
        bytes32 playerPermission = vault.getActionId(0xd9caed12, player, address(vault));
        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = deployerPermission;
        permissions[1] = playerPermission;
        vault.setPermissions(permissions);
        assertTrue(vault.permissions(deployerPermission));
        assertTrue(vault.permissions(playerPermission));

        // make sure vault is initialized
        assertTrue(vault.initialized());

        // deposit tokens into the vault
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(player)), 0);

        // cannot call vault directly
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.sweepFunds(deployer, IERC20(address(token)));
        vm.stopPrank();
        vm.startPrank(player);
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.withdraw(address(token), player, 1e18);
        vm.stopPrank();
    }

    function exploit() public {
        vm.startPrank(player);

        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();

        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(address(player)), 0);
        assertEq(token.balanceOf(address(recovery)), VAULT_TOKEN_BALANCE);
    }
}
