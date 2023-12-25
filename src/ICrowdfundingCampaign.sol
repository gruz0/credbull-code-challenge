// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface ICrowdfundingCampaign {
    function releaseFunds() external;

    function reward() external view;

    function isShareHolder() external view returns (bool);
}
