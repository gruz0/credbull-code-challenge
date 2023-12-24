// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {CrowdfundingCampaign} from "../src/CrowdfundingCampaign.sol";
import {IERC20Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

contract CrowdfundingCampaignTest is Test {
    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    address tokenOwner;
    address platformOwner;
    address campaignOwner;
    address supporter;

    ERC20Mock token;
    CrowdfundingCampaign private campaign;

    function setUp() public {
        tokenOwner = makeAddr("tokenOwner");
        platformOwner = makeAddr("platformOwner");
        campaignOwner = makeAddr("campaignOwner");
        supporter = makeAddr("supporter");

        vm.prank(tokenOwner);

        token = new ERC20Mock();

        vm.prank(platformOwner);

        campaign = new CrowdfundingCampaign({
            asset: token,
            platformOwner: platformOwner,
            campaignOwner: campaignOwner,
            name: "SharesToken",
            symbol: "SHARES",
            donationGoalAmount: 100,
            commissionFeePercentage: 1,
            startTimestamp: uint64(block.timestamp),
            durationSeconds: 1
        });
    }

    function test_Deposit_RevertWhen_ZeroAmount() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 101);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        vm.expectRevert(CrowdfundingCampaign.ZeroDepositAmount.selector);

        campaign.deposit(0, supporter);

        assertFalse(campaign.isShareHolder());

        vm.stopPrank();

        uint256 campaignBalance = token.balanceOf(address(campaign));
        uint256 supporterBalance = token.balanceOf(supporter);

        assertEq(campaignBalance, 0);
        assertEq(supporterBalance, 101);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 0);
    }

    function test_Deposit_RevertWhen_InsufficientAllowance() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 99);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(campaign),
                99,
                100
            )
        );

        campaign.deposit(100, supporter);

        assertFalse(campaign.isShareHolder());
    }

    function test_Deposit_Success_CampaignHasAccessToFunds() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 101);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        vm.stopPrank();

        uint256 campaignBalance = token.balanceOf(address(campaign));
        uint256 supporterBalance = token.balanceOf(supporter);

        assertEq(campaignBalance, 100);
        assertEq(supporterBalance, 1);
    }

    function test_Deposit_WhenExcessAllowance_CampaignHasAccessToExactAssets() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 101);

        vm.startPrank(supporter);

        token.approve(address(campaign), 101);

        campaign.deposit(100, supporter);

        vm.stopPrank();

        uint256 campaignBalance = token.balanceOf(address(campaign));
        uint256 supporterBalance = token.balanceOf(supporter);

        assertEq(campaignBalance, 100);
        assertEq(supporterBalance, 1);
    }

    function test_Deposit_Success_SupporterReceivesShares() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 101);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        assertTrue(campaign.isShareHolder());

        vm.stopPrank();

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 100);
    }

    function test_Deposit_Success_EmitsEvent() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        vm.expectEmit(true, true, true, true);

        emit Deposit(address(supporter), address(supporter), 100, 100);

        campaign.deposit(100, supporter);
    }

    function test_GoalReached_WhenGoalReached_ReturnsTrue() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        assertTrue(campaign.goalReached());
    }

    function test_GoalReached_WhenGoalIsNotReached_ReturnsFalse() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 99);

        vm.startPrank(supporter);

        token.approve(address(campaign), 99);

        campaign.deposit(99, supporter);

        assertFalse(campaign.goalReached());
    }

    function test_Withdraw_RevertWhen_SharesAreLocked() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 100);

        vm.expectRevert(CrowdfundingCampaign.SharesInVestingPeriod.selector);

        campaign.withdraw(1, supporter, supporter);

        uint256 supporterBalance = token.balanceOf(supporter);
        uint256 campaignBalance = token.balanceOf(address(campaign));

        assertEq(supporterBalance, 0);
        assertEq(campaignBalance, 100);

        uint256 supporterSharesAfterWithdrawal = campaign.balanceOf(supporter);

        assertEq(supporterSharesAfterWithdrawal, 100);
    }

    function test_Withdraw_Success_FundsTransferedToTheSupporter() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 100);

        vm.warp(block.timestamp + 1);

        campaign.withdraw(1, supporter, supporter);

        uint256 supporterBalance = token.balanceOf(supporter);
        uint256 campaignBalance = token.balanceOf(address(campaign));

        assertEq(supporterBalance, 1);
        assertEq(campaignBalance, 99);

        uint256 supporterSharesAfterWithdrawal = campaign.balanceOf(supporter);

        assertEq(supporterSharesAfterWithdrawal, 99);
    }

    function test_Withdraw_WhenCampaignGoalIsNotReached_FundsTransferedToTheSupporter() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 99);

        vm.startPrank(supporter);

        token.approve(address(campaign), 99);

        campaign.deposit(99, supporter);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 99);

        vm.warp(block.timestamp + 1);

        campaign.withdraw(99, supporter, supporter);

        uint256 supporterBalance = token.balanceOf(supporter);
        uint256 campaignBalance = token.balanceOf(address(campaign));

        assertEq(supporterBalance, 99);
        assertEq(campaignBalance, 0);

        uint256 supporterSharesAfterWithdrawal = campaign.balanceOf(supporter);

        assertEq(supporterSharesAfterWithdrawal, 0);
    }

    function test_ReleaseFunds_RevertWhen_GoalIsNotReached() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 99);

        campaign.deposit(99, supporter);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 99);

        vm.stopPrank();

        vm.startPrank(campaignOwner);

        vm.expectRevert(CrowdfundingCampaign.GoalIsNotReached.selector);

        campaign.releaseFunds();

        vm.stopPrank();

        uint256 campaignOwnerBalance = token.balanceOf(campaignOwner);
        uint256 campaignBalance = token.balanceOf(address(campaign));

        assertEq(campaignOwnerBalance, 0);
        assertEq(campaignBalance, 99);
    }

    function test_ReleaseFunds_RevertWhen_GoalIsReachedButDateIsNotPassed() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 100);

        vm.stopPrank();

        vm.startPrank(campaignOwner);

        vm.expectRevert(CrowdfundingCampaign.TooEarly.selector);

        campaign.releaseFunds();

        uint256 campaignOwnerBalance = token.balanceOf(campaignOwner);
        uint256 campaignBalance = token.balanceOf(address(campaign));

        assertEq(campaignOwnerBalance, 0);
        assertEq(campaignBalance, 100);
    }

    function test_ReleaseFunds_Success_FundsTransferedToTheOwner() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 100);

        vm.stopPrank();

        vm.warp(block.timestamp + 1);

        vm.startPrank(campaignOwner);

        campaign.releaseFunds();

        uint256 campaignOwnerBalance = token.balanceOf(campaignOwner);
        uint256 platformOwnerBalance = token.balanceOf(platformOwner);
        uint256 campaignBalance = token.balanceOf(address(campaign));

        assertEq(campaignOwnerBalance, 99);
        assertEq(platformOwnerBalance, 1);
        assertEq(campaignBalance, 0);
    }
}
