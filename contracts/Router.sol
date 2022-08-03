// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "./types/Ownable.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IBalancerPool.sol";
import "./interfaces/IBalancerVault.sol";
import "./interfaces/IWeightedPool.sol";
import "./interfaces/IWeightedPoolFactory.sol";
import "./interfaces/IBalancerVault.sol";

contract Router is Ownable {
    using SafeERC20 for IERC20;

    mapping(bytes32 => bytes32) poolIds;

    IWeightedPoolFactory public poolFactory; // balancer poolFactory
    IBalancerVault public vault; // balancer vault
    uint256 public swapFeePercentage; // 18 decimals

    enum JoinKind {
        INIT,
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT,
        ALL_TOKENS_IN_FOR_EXACT_BPT_OUT,
        ADD_TOKEN
    }
    enum ExitKind {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        EXACT_BPT_IN_FOR_TOKENS_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT,
        REMOVE_TOKEN
    }

    constructor(
        IWeightedPoolFactory _poolFactory,
        IBalancerVault _vault,
        uint256 _swapFeePercentage
    ) {
        poolFactory = _poolFactory;
        swapFeePercentage = _swapFeePercentage;
        vault = _vault;
    }

    function _arrayIsSorted(IERC20[] calldata array)
        internal
        pure
        returns (bool)
    {
        if (array.length < 2) {
            return true;
        }

        IERC20 previous = array[0];
        for (uint256 i = 1; i < array.length; ++i) {
            IERC20 current = array[i];
            if (previous >= current) return false;
            previous = current;
        }

        return true;
    }

    function addLiquidity(
        IERC20[] calldata _tokens,
        uint256[] calldata _weights,
        uint256[] calldata _amounts
    ) external {
        require(_arrayIsSorted(_tokens), "Addresses must be sorted");

        bytes32 poolId = _getPoolId(_tokens, _weights);

        IBalancerVault.JoinKind joinKind = IBalancerVault
            .JoinKind
            .EXACT_TOKENS_IN_FOR_BPT_OUT;
        if (poolId == bytes32(0)) {
            poolId = _createPool(_tokens, _weights);
            joinKind = IBalancerVault.JoinKind.INIT;
        }
        _addLiquidityToPool(poolId, _tokens, _amounts, joinKind);
    }

    function _getPoolId(IERC20[] calldata _tokens, uint256[] calldata _weights)
        internal
        view
        returns (bytes32)
    {
        return poolIds[keccak256(abi.encode(_tokens, _weights))];
    }

    function _makeLpName(IERC20[] calldata _tokens, uint256[] calldata _weights)
        internal
        returns (string memory)
    {
        // todo: make correct
        return "A";
    }

    function _makeLpSymbol(
        IERC20[] calldata _tokens,
        uint256[] calldata _weights
    ) internal returns (string memory) {
        // todo: make correct
        return "A";
    }

    function _createPool(IERC20[] calldata _tokens, uint256[] calldata _weights)
        internal
        returns (bytes32 poolId_)
    {
        address[] memory assetManagers_ = new address[](_tokens.length); // all zero

        address poolAddress_ = poolFactory.create(
            _makeLpName(_tokens, _weights),
            _makeLpSymbol(_tokens, _weights),
            _tokens,
            _weights,
            assetManagers_,
            swapFeePercentage,
            address(this)
        );

        poolId_ = IWeightedPool(poolAddress_).getPoolId();
    }

    function _addLiquidityToPool(
        bytes32 _poolId,
        IERC20[] calldata _tokens,
        uint256[] calldata _amounts,
        IBalancerVault.JoinKind joinType
    ) internal {
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20(_tokens[i]).approve(address(vault), _amounts[i]);
        }

        // Put together a JoinPoolRequest type
        IBalancerVault.JoinPoolRequest memory joinRequest;
        joinRequest.assets = _tokens;
        joinRequest.maxAmountsIn = _amounts;
        joinRequest.fromInternalBalance = false;
        if (joinType == IBalancerVault.JoinKind.INIT) {
            joinRequest.userData = abi.encode(JoinKind.INIT, _amounts);
        } else {
            joinRequest.userData = abi.encode(
                JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                _amounts,
                0 // todo: change minimum bpt
            );
        }

        // Tokens are pulled from sender (Or could be an approved relayer)
        vault.joinPool(_poolId, address(this), address(this), joinRequest);
    }
}
