// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./IERC20.sol";
import "./IBalancerVault.sol";

interface IBalancerPool is IERC20 {
    function getPoolId() external view returns (bytes32 poolId);

    function getVault() external view returns (IBalancerVault vault);

    function getInternalBalance(address _user, IERC20[] memory _tokens)
        external
        view
        returns (uint256[] memory);
}
