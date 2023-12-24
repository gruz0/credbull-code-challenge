// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CrowdfundingCampaign is ERC4626, VestingWallet, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event FundsReleased(uint256 amount);

    error ZeroDepositAmount();
    error SharesLocked();
    // FIXME: Rename Goal to Campaign to have more self-explanatory errors
    error GoalIsNotReached();
    error GoalClosed();
    error GoalIsNotClosed();
    error TooEarly();

    IERC20 private immutable _asset;
    address private immutable _platformOwner;
    address private immutable _campaignOwner;
    uint256 private immutable _donationGoalAmount;
    uint8 private immutable _commissionFeePercentage;
    // The following two variables will be used for rewarding mechanism later
    mapping(address supporter => bool hasShares) private _shareHolders;
    address[] private _supporters;

    // We may want to have these variables with public modifiers to provide better UX in the UI
    bool public goalReached = false;
    bool public goalClosed = false;

    constructor(
        IERC20 asset,
        address platformOwner,
        address campaignOwner,
        string memory name,
        string memory symbol,
        uint256 donationGoalAmount,
        uint8 commissionFeePercentage,
        uint64 startTimestamp,
        uint64 durationSeconds
    )
      ERC4626(asset)
      ERC20(name, symbol)
      VestingWallet(campaignOwner, startTimestamp, durationSeconds)
    {
        require(platformOwner != address(0), "Platform owner zero address");
        require(campaignOwner != address(0), "Campaign owner zero address");

        _asset = asset;
        _platformOwner = platformOwner;
        _campaignOwner = campaignOwner;
        _donationGoalAmount = donationGoalAmount;
        _commissionFeePercentage = commissionFeePercentage;
    }

    function deposit(
        uint256 assets,
        address receiver
    ) public override returns (uint256 shares) {
        if (assets == 0) revert ZeroDepositAmount();
        if (goalClosed) revert GoalClosed();

        shares = super.deposit(assets, receiver);

        if (_asset.balanceOf(address(this)) >= _donationGoalAmount) {
            goalReached = true;
        }

        _shareHolders[receiver] = true;
        _supporters.push(receiver);

        return shares;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        if (goalClosed) revert GoalClosed();

        if (assets > releasable(address(_asset))) {
            revert SharesLocked();
        }

        shares = super.withdraw(assets, receiver, owner);

        if (goalReached && _asset.balanceOf(address(this)) < _donationGoalAmount) {
            goalReached = false;
        }

        _shareHolders[msg.sender] = this.balanceOf(owner) > 0;
        _shareHolders[receiver] = this.balanceOf(receiver) > 0;

        return shares;
    }

    function isShareHolder() external view returns (bool) {
        return _shareHolders[msg.sender];
    }

    function releaseFunds() external onlyOwner nonReentrant {
        if (!goalReached) revert GoalIsNotReached();

        if (goalClosed) revert GoalClosed();

        uint256 assets = _asset.balanceOf(address(this));

        if (assets > releasable(address(_asset))) {
            revert TooEarly();
        }

        goalClosed = true;

        emit FundsReleased(assets);

        // NOTE: We don't want to burn shares here,
        // because its will be used for sending NFTs as a reward

        uint256 fees = (assets * _commissionFeePercentage) / 100;

        SafeERC20.safeTransfer(_asset, _platformOwner, fees);
        SafeERC20.safeTransfer(_asset, _campaignOwner, assets - fees);
    }

    function reward() external view onlyOwner {
        if (!goalReached) revert GoalIsNotReached();
        if (!goalClosed) revert GoalIsNotClosed();

        // Used to send NFTs as a reward when campaign is succeed
    }

    function cancel() external onlyOwner {
        // We may want to have this function if campaign owner decides to stop their campaign
        // In this case, we can unlock all tokens for shareholders
    }
}
