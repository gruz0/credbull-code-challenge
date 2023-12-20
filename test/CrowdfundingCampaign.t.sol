// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {CrowdfundingCampaign} from "../src/CrowdfundingCampaign.sol";

contract CrowdfundingCampaignTest is Test {
    CrowdfundingCampaign private campaign;

    event Deposit(address indexed supporter, uint256 amount);

    address deployer;
    address campaignOwner;
    address tokenOwner;
    address supporter;

    ERC20Mock token;

    function setUp() public {
        deployer = makeAddr("deployer");
        campaignOwner = makeAddr("campaignOwner");
        tokenOwner = makeAddr("tokenOwner");
        supporter = makeAddr("supporter");

        vm.prank(tokenOwner);

        token = new ERC20Mock();

        vm.prank(deployer);

        campaign = new CrowdfundingCampaign(campaignOwner, token);
    }

    function test_Deposit_RevertWhen_AmountIsZero() public {
        vm.expectRevert(CrowdfundingCampaign.ZeroDepositAmount.selector);

        vm.prank(supporter);

        campaign.deposit(0);
    }

    function test_Deposit_RevertWhen_InsufficientAllowance() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 99);

        vm.expectRevert(CrowdfundingCampaign.InsufficientAllowance.selector);

        campaign.deposit(100);
    }

    function test_Deposit_Success_CampaignHasAccessToFunds() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);
        campaign.deposit(100);

        vm.stopPrank();

        uint256 campaignBalance = token.balanceOf(address(campaign));
        uint256 supporterBalance = token.balanceOf(supporter);

        assertEq(campaignBalance, 100);
        assertEq(supporterBalance, 0);
    }

    function test_Deposit_Success_EmitsEvent() public {
        vm.prank(tokenOwner);

        token.mint(address(supporter), 100);

        vm.startPrank(supporter);

        token.approve(address(campaign), 100);

        vm.expectEmit(true, true, true, true);

        emit Deposit(address(supporter), 100);

        campaign.deposit(100);
    }
}
