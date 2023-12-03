// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {AuthorizerUpgradeable} from "../../src/wallet-mining/AuthorizerUpgradeable.sol";
import {WalletDeployer} from "../../src/wallet-mining/WalletDeployer.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract WalletMiningTest is Test {
    address public deployer;
    address public player;
    address public wards;

    DamnValuableToken public token;
    WalletDeployer public walletDeployer;
    AuthorizerUpgradeable public authorizer;

    address public constant DEPOSIT_ADDRESS = 0x9B6fb606A9f5789444c17768c6dFCF2f83563801;
    uint256 public constant DEPOSIT_TOKEN_AMOUNT = 20000000e18;
    uint256 public initialWalletDeployerTokenBalance;

    function setUp() public {
        deployer = makeAddr("deployer");
        player = makeAddr("player");
        wards = makeAddr("wards");

        vm.startPrank(deployer);
        token = new DamnValuableToken();

        AuthorizerUpgradeable authorizerImplementation = new AuthorizerUpgradeable();
        address[] memory _wards = new address[](1);
        address[] memory _aims = new address[](1);
        _wards[0] = wards;
        _aims[0] = DEPOSIT_ADDRESS;
        bytes memory data = abi.encodeWithSelector(authorizerImplementation.init.selector, _wards, _aims);

        ERC1967Proxy authorizerProxy = new ERC1967Proxy(address(authorizerImplementation), data);

        authorizer = AuthorizerUpgradeable(address(authorizerProxy));

        assertEq(authorizer.owner(), deployer);
        assertEq(authorizer.can(wards, DEPOSIT_ADDRESS), true);
        assertEq(authorizer.can(player, DEPOSIT_ADDRESS), false);

        walletDeployer = new WalletDeployer(address(token));
        assertEq(walletDeployer.chief(), deployer);
        assertEq(walletDeployer.gem(), address(token));

        walletDeployer.rule(address(authorizer));
        assertEq(walletDeployer.mom(), address(authorizer));
        assertEq(walletDeployer.can(wards, DEPOSIT_ADDRESS), true);
        // vm.expectRevert("EvmError: Revert");
        // walletDeployer.can(player, DEPOSIT_ADDRESS);

        initialWalletDeployerTokenBalance = walletDeployer.pay() * 43;
        token.transfer(address(walletDeployer), initialWalletDeployerTokenBalance);

        assertEq(DEPOSIT_ADDRESS.code.length, 0);
        assertEq(address(walletDeployer.fact()).code.length, 0);
        assertEq(address(walletDeployer.copy()).code.length, 0);

        token.transfer(DEPOSIT_ADDRESS, DEPOSIT_TOKEN_AMOUNT);
        assertEq(token.balanceOf(DEPOSIT_ADDRESS), DEPOSIT_TOKEN_AMOUNT);
        assertEq(token.balanceOf(address(walletDeployer)), initialWalletDeployerTokenBalance);
        assertEq(token.balanceOf(address(player)), 0);

        vm.stopPrank();
    }

    function exploit() public {
        vm.startPrank(player);

        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();

        // Factory account must have code
        assertTrue(address(walletDeployer.fact()).code.length != 0);

        // Master copy account must have code
        assertTrue(address(walletDeployer.copy()).code.length != 0);

        // Deposit account must have code
        assertTrue(DEPOSIT_ADDRESS.code.length != 0);

        // The deposit address and the Safe Deployer contract must not hold tokens
        assertEq(token.balanceOf(DEPOSIT_ADDRESS), 0);
        assertEq(token.balanceOf(address(walletDeployer)), 0);

        // Player must own all tokens
        assertEq(token.balanceOf(address(player)), initialWalletDeployerTokenBalance + DEPOSIT_TOKEN_AMOUNT);
    }
}
