// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {CrowdfundingCampaign} from "../src/CrowdfundingCampaign.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {TestAvatar} from "@gnosis.pm/zodiac/contracts/test/TestAvatar.sol";
import {CampaignGuard} from "../src/CampaignGuard.sol";
import {TimelockModifier} from "../src/TimelockModifier.sol";

contract CrowdfundingCampaignTest is Test {
    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    uint64 private campaignDuration = 3 minutes;

    ERC20Mock private token;
    TestAvatar private safe;
    CampaignGuard private campaignGuard;
    CrowdfundingCampaign private campaign;
    TimelockModifier private timelock;

    address private platformOwner;
    address private campaignOwner;

    function setUp() public {
        platformOwner = makeAddr("platformOwner");
        campaignOwner = makeAddr("campaignOwner");

        safe = new TestAvatar();

        token = new ERC20Mock();

        campaign = new CrowdfundingCampaign({
            asset: token,
            platformOwner: platformOwner,
            campaignOwner: campaignOwner,
            name: "SharesToken",
            symbol: "SHARES",
            donationGoalAmount: 100,
            commissionFeePercentage: 1,
            startTimestamp: uint64(block.timestamp),
            durationSeconds: campaignDuration
        });
        campaign.transferOwnership(address(safe));

        timelock = new TimelockModifier({
            _avatar: address(safe),
            _target: address(safe),
            _start: uint64(block.timestamp),
            _duration: campaignDuration
        });

        safe.enableModule(address(timelock));

        campaignGuard = new CampaignGuard({
            _owner: address(timelock),
            _campaign: address(campaign),
            _campaignOwner: campaignOwner
        });

        timelock.enableModule(address(campaignGuard));
        timelock.transferOwnership(address(safe));
    }

    function test_Deposit_RevertWhen_ZeroAmount() public {
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 101);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        vm.expectRevert(CrowdfundingCampaign.ZeroDepositAmount.selector);

        campaign.deposit(0, supporter);

        vm.stopPrank();

        uint256 campaignBalance = token.balanceOf(address(campaign));
        uint256 supporterBalance = token.balanceOf(supporter);

        assertEq(campaignBalance, 0);
        assertEq(supporterBalance, 101);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 0);
    }

    function test_Deposit_RevertWhen_InsufficientAllowance() public {
        address supporter = makeAddr("supporter");

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
    }

    function test_Deposit_Success_CampaignHasAccessToFunds() public {
        address supporter = makeAddr("supporter");

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
        address supporter = makeAddr("supporter");

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
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 101);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        vm.stopPrank();

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 100);
    }

    function test_Deposit_Success_EmitsEvent() public {
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        vm.expectEmit(true, true, true, true);

        emit Deposit(address(supporter), address(supporter), 100, 100);

        campaign.deposit(100, supporter);
    }

    function test_GoalReached_WhenGoalReached_ReturnsTrue() public {
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        assertTrue(campaign.goalReached());
    }

    function test_GoalReached_WhenGoalIsNotReached_ReturnsFalse() public {
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 99);

        vm.startPrank(supporter);

        token.approve(address(campaign), 99);

        campaign.deposit(99, supporter);

        assertFalse(campaign.goalReached());
    }

    function test_Withdraw_RevertWhen_DirectAccessToTheCampaign() public {
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address(supporter)
            )
        );

        campaign.withdraw(1, supporter, supporter);
    }

    function test_Withdraw_RevertWhen_SharesAreLocked() public {
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 100);

        vm.expectRevert(TimelockModifier.TransactionsTimelocked.selector);

        campaignGuard.withdraw(1, supporter, supporter);

        uint256 supporterBalance = token.balanceOf(supporter);
        uint256 campaignBalance = token.balanceOf(address(campaign));

        assertEq(supporterBalance, 0);
        assertEq(campaignBalance, 100);

        uint256 supporterSharesAfterWithdrawal = campaign.balanceOf(supporter);

        assertEq(supporterSharesAfterWithdrawal, 100);
    }

    function test_Withdraw_Success_FundsTransferedToTheSupporter() public {
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 100);

        vm.warp(block.timestamp + campaignDuration);

        campaign.approve(address(safe), 1);

        campaignGuard.withdraw(1, supporter, supporter);

        uint256 supporterBalance = token.balanceOf(supporter);
        uint256 campaignBalance = token.balanceOf(address(campaign));

        assertEq(supporterBalance, 1);
        assertEq(campaignBalance, 99);

        uint256 supporterSharesAfterWithdrawal = campaign.balanceOf(supporter);

        assertEq(supporterSharesAfterWithdrawal, 99);
    }

    function test_Withdraw_WhenCampaignGoalIsNotReached_FundsTransferedToTheSupporter() public {
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 99);

        vm.startPrank(supporter);

        token.approve(address(campaign), 99);

        campaign.deposit(99, supporter);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 99);

        vm.warp(block.timestamp + campaignDuration);

        campaign.approve(address(safe), 98);

        campaignGuard.withdraw(98, supporter, supporter);

        uint256 supporterBalance = token.balanceOf(supporter);
        uint256 campaignBalance = token.balanceOf(address(campaign));

        assertEq(supporterBalance, 98);
        assertEq(campaignBalance, 1);

        uint256 supporterSharesAfterWithdrawal = campaign.balanceOf(supporter);

        assertEq(supporterSharesAfterWithdrawal, 1);
    }

    function test_ReleaseFunds_RevertWhen_NotACampaignOwner() public {
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 99);

        campaign.deposit(99, supporter);

        vm.warp(block.timestamp + campaignDuration);

        vm.expectRevert(CampaignGuard.CampaignOwnerOnly.selector);

        campaignGuard.releaseFunds();
    }

    function test_ReleaseFunds_RevertWhen_TooEarly() public {
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 99);

        campaign.deposit(99, supporter);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 99);

        vm.stopPrank();

        vm.startPrank(campaignOwner);

        vm.expectRevert(TimelockModifier.TransactionsTimelocked.selector);

        campaignGuard.releaseFunds();

        vm.stopPrank();

        uint256 campaignOwnerBalance = token.balanceOf(campaignOwner);
        uint256 campaignBalance = token.balanceOf(address(campaign));

        assertEq(campaignOwnerBalance, 0);
        assertEq(campaignBalance, 99);
    }

    function test_ReleaseFunds_RevertWhen_GoalIsNotReached() public {
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 99);

        campaign.deposit(99, supporter);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 99);

        vm.stopPrank();

        vm.warp(block.timestamp + campaignDuration);

        vm.startPrank(campaignOwner);

        vm.expectRevert(CrowdfundingCampaign.GoalIsNotReached.selector);

        campaignGuard.releaseFunds();

        vm.stopPrank();

        uint256 campaignOwnerBalance = token.balanceOf(campaignOwner);
        uint256 campaignBalance = token.balanceOf(address(campaign));

        assertEq(campaignOwnerBalance, 0);
        assertEq(campaignBalance, 99);
    }

    function test_ReleaseFunds_RevertWhen_GoalIsReachedButDateIsNotPassed() public {
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 100);

        vm.stopPrank();

        vm.warp(block.timestamp + campaignDuration - 1);

        vm.startPrank(campaignOwner);

        vm.expectRevert(TimelockModifier.TransactionsTimelocked.selector);

        campaignGuard.releaseFunds();

        uint256 campaignOwnerBalance = token.balanceOf(campaignOwner);
        uint256 campaignBalance = token.balanceOf(address(campaign));

        assertEq(campaignOwnerBalance, 0);
        assertEq(campaignBalance, 100);
    }

    function test_ReleaseFunds_Success_FundsTransferedToTheOwner() public {
        address supporter = makeAddr("supporter");

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        campaign.deposit(100, supporter);

        uint256 supporterShares = campaign.balanceOf(supporter);

        assertEq(supporterShares, 100);

        vm.stopPrank();

        vm.warp(block.timestamp + campaignDuration);

        vm.startPrank(campaignOwner);

        campaignGuard.releaseFunds();

        uint256 campaignOwnerBalance = token.balanceOf(campaignOwner);
        uint256 platformOwnerBalance = token.balanceOf(platformOwner);
        uint256 campaignBalance = token.balanceOf(address(campaign));

        assertEq(campaignOwnerBalance, 99);
        assertEq(platformOwnerBalance, 1);
        assertEq(campaignBalance, 0);
    }

    function test_RewardSupporters_Success() public {
        address supporter1 = makeAddr("supporter1");
        address supporter2 = makeAddr("supporter2");
        address supporter3 = makeAddr("supporter3");

        token.mint(address(supporter1), 50);
        token.mint(address(supporter2), 25);
        token.mint(address(supporter3), 25);

        // Supporter1 donated twice, but will be stored as a supporter only once
        vm.startPrank(supporter1);
        token.approve(address(campaign), 50);
        campaign.deposit(30, supporter1);
        campaign.deposit(20, supporter1);
        vm.stopPrank();

        vm.startPrank(supporter2);
        token.approve(address(campaign), 25);
        campaign.deposit(25, supporter2);
        vm.stopPrank();

        vm.startPrank(supporter3);
        token.approve(address(campaign), 25);
        campaign.deposit(25, supporter3);
        vm.stopPrank();

        vm.warp(block.timestamp + campaignDuration);

        vm.startPrank(campaignOwner);

        campaignGuard.releaseFunds();

        campaignGuard.rewardSupporters();
    }
}
