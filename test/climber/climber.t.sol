// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "../../src/climber/ClimberVault.sol";
import "../../src/climber/ClimberTimelock.sol";
import "../../src/climber/ClimberConstants.sol";
import "../../src/DamnValuableToken.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ClimberTest is Test {
    address public deployer;
    address public player;
    address proposer;
    address sweeper;

    address public timelockAddress;
    ClimberVault public vault;
    ClimberTimelock public timelock;
    DamnValuableToken public token;

    uint256 public constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 public constant PLAYER_INITIAL_ETH_BALANCE = 1e17;
    uint256 public constant TIMELOCK_DELAY = 60 * 60;

    function setUp() public {
        deployer = makeAddr("deployer");
        player = makeAddr("player");
        proposer = makeAddr("proposer");
        sweeper = makeAddr("sweeper");

        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(address(player).balance, PLAYER_INITIAL_ETH_BALANCE);
        vm.startPrank(deployer);

        ClimberVault vaultImplementation = new ClimberVault();

        bytes memory data = abi.encodeWithSelector(vaultImplementation.initialize.selector, deployer, proposer, sweeper);
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImplementation), data);
        vault = ClimberVault(address(vaultProxy));

        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertTrue(vault.owner() != address(0));
        assertTrue(vault.owner() != address(deployer));

        timelockAddress = vault.owner();
        timelock = ClimberTimelock(payable(timelockAddress));

        assertEq(timelock.delay(), TIMELOCK_DELAY);

        assertEq(timelock.hasRole(PROPOSER_ROLE, proposer), true);
        assertEq(timelock.hasRole(ADMIN_ROLE, deployer), true);
        assertEq(timelock.hasRole(ADMIN_ROLE, timelockAddress), true);

        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        vm.stopPrank();
    }

    function exploit() public {
        vm.startPrank(player);

        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(address(player)), VAULT_TOKEN_BALANCE);
    }
}
