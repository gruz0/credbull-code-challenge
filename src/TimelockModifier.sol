// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Modifier, Enum} from "@gnosis.pm/zodiac/contracts/core/Modifier.sol";

contract TimelockModifier is Modifier {
    error TransactionsTimelocked();

    uint64 private startTimestamp;
    uint64 private durationSeconds;

    constructor(address _avatar, address _target, uint64 _start, uint64 _duration) {
        bytes memory initParams = abi.encode(_avatar, _target, _start, _duration);
        setUp(initParams);
    }

    function setUp(bytes memory initParams) public override initializer {
        __Ownable_init(_msgSender());

        (address _avatar, address _target, uint64 _start, uint64 _duration) =
            abi.decode(initParams, (address, address, uint64, uint64));

        avatar = _avatar;
        target = _target;
        startTimestamp = _start;
        durationSeconds = _duration;

        setupModules();
    }

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    )
        public
        override
        moduleOnly
        returns (bool success)
    {
        if (!canExecute(uint64(block.timestamp))) revert TransactionsTimelocked();

        return exec(to, value, data, operation);
    }

    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) public override moduleOnly returns (bool success, bytes memory returnData) {
        if (!canExecute(uint64(block.timestamp))) revert TransactionsTimelocked();

        return execAndReturnData(to, value, data, operation);
    }

    function canExecute(uint64 timestamp) private view returns (bool) {
        return timestamp >= (startTimestamp + durationSeconds);
    }
}
