// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICrowdfundingCampaign} from "./ICrowdfundingCampaign.sol";

contract CrowdfundingCampaign is ICrowdfundingCampaign, ERC4626, Ownable {
    using SafeERC20 for IERC20;

    event FundsRequested(uint256 amount);

    error CampaignIsNotStarted();
    error PlatformOwnerZeroAddress();
    error CampaignOwnerZeroAddress();
    error DonationGoalIsZero();
    error InvalidCommissionPercentage();
    error InvalidStartDate();
    error ZeroDepositAmount();
    error GoalIsNotReached();
    error GoalClosed();
    error GoalIsNotClosed();

    IERC20 private immutable _asset;
    address private immutable _platformOwner;
    address private immutable _campaignOwner;
    uint256 private immutable _fundingGoal;
    uint8 private immutable _commissionFeePercentage;
    mapping(address => bool) private _supporterExists;
    address[] private _supporters;
    uint64 private _startTimestamp;

    // We may want to have these variables with public modifiers to provide better UX in the UI
    bool public goalReached = false;
    bool public goalClosed = false;

    constructor(
        IERC20 asset,
        address platformOwner,
        address campaignOwner,
        string memory shareTokenName,
        string memory shareTokenSymbol,
        uint256 fundingGoal,
        uint8 commissionFeePercentage,
        uint64 startTimestamp
    )
      ERC4626(asset)
      ERC20(shareTokenName, shareTokenSymbol)
      Ownable(_msgSender())
    {
        if (platformOwner == address(0)) revert PlatformOwnerZeroAddress();
        if (campaignOwner == address(0)) revert CampaignOwnerZeroAddress();
        if (fundingGoal == 0) revert DonationGoalIsZero();
        if (commissionFeePercentage >= 100) revert InvalidCommissionPercentage();
        if (startTimestamp < block.timestamp) revert InvalidStartDate();

        _asset = asset;
        _platformOwner = platformOwner;
        _campaignOwner = campaignOwner;
        _fundingGoal = fundingGoal;
        _commissionFeePercentage = commissionFeePercentage;
        _startTimestamp = startTimestamp;
    }

    // @dev We have to override this function to block an external access
    function mint(uint256 shares, address receiver) public override onlyOwner returns (uint256) {
        return super.mint(shares, receiver);
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (assets == 0) revert ZeroDepositAmount();
        if (goalClosed) revert GoalClosed();
        if (block.timestamp < _startTimestamp) revert CampaignIsNotStarted();

        super._deposit(caller, receiver, assets, shares);

        if (!goalReached && _asset.balanceOf(address(this)) >= _fundingGoal) {
            goalReached = true;
        }

        // We want to keep only unique supporters, no matter how many deposits they made
        if (!_supporterExists[receiver]) {
            _supporterExists[receiver] = true;

            _supporters.push(receiver);
        }
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
    }

    function requestFunds() external onlyOwner {
        if (!goalReached) revert GoalIsNotReached();

        if (goalClosed) revert GoalClosed();

        uint256 assets = _asset.balanceOf(address(this));

        goalClosed = true;

        emit FundsRequested(assets);

        if (_commissionFeePercentage > 0) {
            uint256 fees = (assets * _commissionFeePercentage) / 100;

            SafeERC20.safeTransfer(_asset, _platformOwner, fees);
            SafeERC20.safeTransfer(_asset, _campaignOwner, assets - fees);

            return;
        }

        SafeERC20.safeTransfer(_asset, _campaignOwner, assets);
    }

    // @dev Used to send NFTs as a reward when campaign is succeed
    function rewardSupporters() external view onlyOwner {
        if (!goalReached) revert GoalIsNotReached();
        if (!goalClosed) revert GoalIsNotClosed();

        uint256 supportersLength = _supporters.length;

        for (uint256 idx = 0; idx < supportersLength; idx++) {
            // TODO: Transfer or mint NFTs here
            console.log(_supporters[idx]);
        }
    }
}
