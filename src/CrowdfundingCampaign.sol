// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICrowdfundingCampaign} from "./ICrowdfundingCampaign.sol";

contract CrowdfundingCampaign is ICrowdfundingCampaign, ERC4626, VestingWallet {
    using SafeERC20 for IERC20;

    event FundsReleased(uint256 amount);

    error PlatformOwnerZeroAddress();
    error CampaignOwnerZeroAddress();
    error DonationGoalIsZero();
    error InvalidCommissionPercentage();
    error ZeroDepositAmount();
    // FIXME: Rename Goal to Campaign to have more self-explanatory errors
    error GoalIsNotReached();
    error GoalClosed();
    error GoalIsNotClosed();

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
      VestingWallet(_msgSender(), startTimestamp, durationSeconds)
    {
        if (platformOwner == address(0)) revert PlatformOwnerZeroAddress();
        if (campaignOwner == address(0)) revert CampaignOwnerZeroAddress();
        if (donationGoalAmount == 0) revert DonationGoalIsZero();
        if (commissionFeePercentage >= 100) revert InvalidCommissionPercentage();

        _asset = asset;
        _platformOwner = platformOwner;
        _campaignOwner = campaignOwner;
        _donationGoalAmount = donationGoalAmount;
        _commissionFeePercentage = commissionFeePercentage;
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (assets == 0) revert ZeroDepositAmount();
        if (goalClosed) revert GoalClosed();

        super._deposit(caller, receiver, assets, shares);

        if (!goalReached && _asset.balanceOf(address(this)) >= _donationGoalAmount) {
            goalReached = true;
        }

        _shareHolders[receiver] = true;
        _supporters.push(receiver);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override onlyOwner {
        if (goalClosed) revert GoalClosed();

        super._withdraw(caller, receiver, owner, assets, shares);

        if (goalReached && _asset.balanceOf(address(this)) < _donationGoalAmount) {
            goalReached = false;
        }

        // FIXME: We should test it carefully
        _shareHolders[caller] = this.balanceOf(caller) > 0;
        _shareHolders[owner] = this.balanceOf(owner) > 0;
        _shareHolders[receiver] = this.balanceOf(receiver) > 0;
    }

    function isShareHolder() external view returns (bool) {
        return _shareHolders[msg.sender];
    }

    // FIXME: Give this function more readable name
    function releaseFunds() external onlyOwner {
        if (!goalReached) revert GoalIsNotReached();

        if (goalClosed) revert GoalClosed();

        uint256 assets = _asset.balanceOf(address(this));

        goalClosed = true;

        emit FundsReleased(assets);

        // NOTE: We don't want to burn shares here,
        // because its will be used for sending NFTs as a reward

        uint256 fees = (assets * _commissionFeePercentage) / 100;

        if (fees > 0) {
            SafeERC20.safeTransfer(_asset, _platformOwner, fees);
        }

        SafeERC20.safeTransfer(_asset, _campaignOwner, assets - fees);
    }

    function reward() external view onlyOwner {
        if (!goalReached) revert GoalIsNotReached();
        if (!goalClosed) revert GoalIsNotClosed();

        // Used to send NFTs as a reward when campaign is succeed
    }
}
