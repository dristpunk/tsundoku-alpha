// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./types/Ownable.sol";
import "./types/Strings.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IERC20Metadata.sol";
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

    address public farms; // farms contract

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
        // todo: fix access trouble
        address _farms,
        IWeightedPoolFactory _poolFactory,
        IBalancerVault _vault,
        uint256 _swapFeePercentage
    ) {
        farms = _farms;
        poolFactory = _poolFactory;
        swapFeePercentage = _swapFeePercentage;
        vault = _vault;
    }

    function addLiquidity(
        bytes32 _poolId,
        IERC20[] calldata _tokens,
        uint256[] calldata _amounts
    ) external {
        _addLiquidityToPool(
            _poolId,
            _tokens,
            _amounts,
            IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT
        );
    }

    function createPool(
        IERC20[] calldata _tokens,
        uint256[] calldata _weights,
        uint256[] calldata _amounts
    ) external returns (bytes32 poolId) {
        poolId = _getPoolId(_tokens, _weights);
        require(poolId == bytes32(0), "Router::Pool already exists");

        poolId = _createPool(_tokens, _weights);

        _addLiquidityToPool(
            poolId,
            _tokens,
            _amounts,
            IBalancerVault.JoinKind.INIT
        );
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
        view
        returns (string memory text_)
    {
        // todo: make correct
        text_ = string.concat(text_, "Tsundoku");
        for (uint256 i = 1; i < _tokens.length; ++i) {
            text_ = string.concat(text_, " ");
            text_ = string.concat(text_, Strings.toString(_weights[i] / 1e18));
            text_ = string.concat(text_, " ");
            string memory tokenSymbol = IERC20Metadata(address(_tokens[i]))
                .symbol();
            text_ = string.concat(text_, tokenSymbol);
        }
    }

    function _makeLpSymbol(
        IERC20[] calldata _tokens,
        uint256[] calldata _weights
    ) internal view returns (string memory text_) {
        // todo: make correct
        text_ = string.concat(text_, "T");
        for (uint256 i = 1; i < _tokens.length; ++i) {
            text_ = string.concat(text_, "-");
            text_ = string.concat(text_, Strings.toString(_weights[i] / 1e18));
            string memory tokenSymbol = IERC20Metadata(address(_tokens[i]))
                .symbol();
            text_ = string.concat(text_, tokenSymbol);
        }
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

        poolIds[keccak256(abi.encode(_tokens, _weights))] = poolId_;
    }

    function _addLiquidityToPool(
        bytes32 _poolId,
        IERC20[] calldata _tokens,
        uint256[] calldata _amounts,
        IBalancerVault.JoinKind joinKind
    ) internal {
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20(_tokens[i]).approve(address(vault), _amounts[i]);
        }

        // Put together a JoinPoolRequest type
        IBalancerVault.JoinPoolRequest memory joinRequest;
        joinRequest.assets = _tokens;
        joinRequest.maxAmountsIn = _amounts;
        joinRequest.fromInternalBalance = false;
        if (joinKind == IBalancerVault.JoinKind.INIT) {
            joinRequest.userData = abi.encode(JoinKind.INIT, _amounts);
        } else {
            joinRequest.userData = abi.encode(
                JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                _amounts,
                0 // todo: change minimum bpt https://dev.balancer.fi/resources/query-batchswap-join-exit#queryexit
            );
        }

        // Tokens are pulled from sender (Or could be an approved relayer)
        vault.joinPool(_poolId, address(this), address(this), joinRequest);
    }

    function removeLiquidity(
        bytes32 _poolId,
        IERC20[] calldata _tokens,
        uint256[] calldata _amounts
    ) external {
        _removeLiquidityFromPool(
            _poolId,
            _tokens,
            _amounts,
            IBalancerVault.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT
        );
    }

    function _removeLiquidityFromPool(
        bytes32 _poolId,
        IERC20[] calldata _tokens,
        uint256[] calldata _amounts,
        IBalancerVault.ExitKind exitKind
    ) internal {
        // Put together a JoinPoolRequest type
        IBalancerVault.ExitPoolRequest memory exitRequest;
        exitRequest.assets = _tokens;
        exitRequest.minAmountsOut = _amounts;
        exitRequest.toInternalBalance = false;

        exitRequest.userData = abi.encode(
            exitKind,
            _amounts,
            2**256 - 1 // todo: change maximum bpt https://dev.balancer.fi/resources/query-batchswap-join-exit#queryexit
        );

        vault.exitPool(_poolId, address(this), address(farms), exitRequest);
    }
}
