// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title CrowdfundingCampaign
/// @dev A smart contract for managing crowdfunding campaigns with ERC20 token support.
contract CrowdfundingCampaign is Ownable {
    /// @dev The ERC20 token used for contributions.
    IERC20 public token;

    /// @dev Emitted when a supporter makes a deposit.
    event Deposit(address indexed supporter, uint256 amount);

    /// @dev Error thrown if the owner address is zero.
    error OwnerZeroAddress();

    /// @dev Error thrown if the provided token address is zero.
    error TokenZeroAddress();

    /// @dev Error thrown if the deposit amount is zero.
    error ZeroDepositAmount();

    /// @dev Error thrown if the supporter's allowance is insufficient.
    error InsufficientAllowance();

    /// @param _owner The address that will own the contract.
    /// @param _token The ERC20 token used for contributions.
    constructor(address _owner, IERC20 _token) Ownable(_owner) {
        if (_owner == address(0)) revert OwnerZeroAddress();
        if (address(_token) == address(0)) revert TokenZeroAddress();

        token = _token;
    }

    /// @dev Allows a supporter to deposit tokens into the contract.
    /// @param amount The amount of tokens to deposit.
    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroDepositAmount();

        if (token.allowance(msg.sender, address(this)) < amount) revert InsufficientAllowance();

        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        emit Deposit(msg.sender, amount);
    }
}
