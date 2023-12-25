// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Enum, Module} from "@gnosis.pm/zodiac/contracts/core/Module.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ICrowdfundingCampaign} from "./ICrowdfundingCampaign.sol";

contract CampaignGuard is Module {
    error CampaignOwnerOnly();

    address private campaign;
    address private campaignOwner;

    constructor(address _owner, address _campaign, address _campaignOwner) {
        bytes memory initializeParams = abi.encode(_owner, _campaign, _campaignOwner);
        setUp(initializeParams);
    }

    function setUp(bytes memory initializeParams) public override initializer {
        __Ownable_init(_msgSender());

        (
            address _owner,
            address _campaign,
            address _campaignOwner
        ) = abi.decode(initializeParams, (address, address, address));

        campaign = _campaign;
        campaignOwner = _campaignOwner;
        setAvatar(_owner);
        setTarget(_owner);
        transferOwnership(_owner);
    }

    function withdraw(uint256 assets, address receiver, address owner) external {
        (bool success, bytes memory data) = execAndReturnData(
            campaign,
            0,
            abi.encodeWithSelector(
                IERC4626.withdraw.selector,
                assets,
                receiver,
                owner
            ),
            Enum.Operation.Call
        );

        if (!success) {
            if (data.length == 0) revert();

            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }

    function redeem(uint256 shares, address receiver, address owner) external {
        (bool success, bytes memory data) = execAndReturnData(
            campaign,
            0,
            abi.encodeWithSelector(
                IERC4626.redeem.selector,
                shares,
                receiver,
                owner
            ),
            Enum.Operation.Call
        );

        if (!success) {
            if (data.length == 0) revert();

            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }

    function requestFunds() external {
        if (msg.sender != campaignOwner) revert CampaignOwnerOnly();

        (bool success, bytes memory data) = execAndReturnData(
            campaign,
            0,
            abi.encodeWithSelector(ICrowdfundingCampaign.requestFunds.selector),
            Enum.Operation.Call
        );

        if (!success) {
            if (data.length == 0) revert();

            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }

    function rewardSupporters() external {
        if (msg.sender != campaignOwner) revert CampaignOwnerOnly();

        (bool success, bytes memory data) = execAndReturnData(
            campaign,
            0,
            abi.encodeWithSelector(ICrowdfundingCampaign.rewardSupporters.selector),
            Enum.Operation.Call
        );

        if (!success) {
            if (data.length == 0) revert();

            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }
}
