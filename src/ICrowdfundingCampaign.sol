// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface ICrowdfundingCampaign {
    function requestFunds() external;

    function rewardSupporters() external;
}
