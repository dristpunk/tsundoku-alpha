// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./IERC20.sol";

interface IWeightedPoolFactory {
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256[] memory weights,
        address[] memory assetManagers,
        uint256 swapFeePercentage,
        address owner
    ) external returns (address);
}
