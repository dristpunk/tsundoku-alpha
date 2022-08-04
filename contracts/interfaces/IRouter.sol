// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "./IERC20.sol";

interface IRouter {
    function addLiquidity(
        bytes32 _poolId,
        IERC20[] calldata _tokens,
        uint256[] calldata _amounts
    ) external;

    function createPool(
        IERC20[] calldata _tokens,
        uint256[] calldata _weights,
        uint256[] calldata _amounts
    ) external returns (bytes32);
}
