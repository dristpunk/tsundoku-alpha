// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "./types/Ownable.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IBalancerPool.sol";
import "./interfaces/IBalancerVault.sol";
import "./tokens/TsundokuToken.sol";
import "./Router.sol";

struct UserInfo {
    uint256 amount; // How many tokens user has provided
    uint256 rewardDebt; // reward debt
}

struct TokenInfo {
    uint256 allocPoint;
    uint256 accDokuPerShare;
    uint256 lastRewardBlock;
    uint256 amount;
}

contract Farms is Ownable {
    using SafeERC20 for IERC20;

    // users info
    mapping(IERC20 => mapping(address => UserInfo)) public users;
    // tokens info
    mapping(IERC20 => TokenInfo) public tokens;
    // tsundoku reward token
    TsundokuToken doku;
    // doku reward for 1 block
    uint256 public dokuPerBlock;
    // sum of all allocPoints of all tokens
    uint256 public totalAllocPoint = 0;
    // The block number when DOKU minting starts.
    uint256 public startBlock;
    // Treasury address
    address public treasury;
    // router contract serves to interact with balancer
    address public router;
    // treasury percent from each token reward (1000 = 100%)
    uint256 public treasuryPercent; // 1 decimal
    // allowed tokens to farm
    IERC20[] public tokenWhitelist;
    mapping(IERC20 => bool) public tokenWhitelistMap;
    // constant for precision computations accDokuPerShare
    uint256 public constant ACCOUNT_PRECISION = 1e12;

    constructor(
        uint256 _dokuPerBlock,
        uint256 _startBlock,
        uint256 _treasuryPercent
    ) {
        dokuPerBlock = _dokuPerBlock;
        startBlock = _startBlock;
        treasuryPercent = _treasuryPercent;
    }

    function initialize(
        TsundokuToken _doku,
        address _treasury,
        address _router
    ) external onlyOwner {
        require(address(doku) == address(0), "Doku address already set");
        require(
            address(treasury) == address(0),
            "Treasury address already set"
        );
        doku = _doku;
        treasury = _treasury;
        router = _router;
    }

    function addToken(IERC20 _token) external onlyOwner {
        tokenWhitelist.push(_token);
        tokenWhitelistMap[_token] = true;
    }

    function removeToken(uint256 _index) external onlyOwner {
        tokenWhitelist[_index] = tokenWhitelist[tokenWhitelist.length - 1];
        tokenWhitelist.pop();
        tokenWhitelistMap[tokenWhitelist[_index]] = false;
    }

    function tokenWhitelistLength() external view returns (uint256) {
        return tokenWhitelist.length;
    }

    function tokenInWhitelist(IERC20 _token) public view returns (bool) {
        return tokenWhitelistMap[_token];
    }

    // update given token info
    function setToken(IERC20 _token, uint256 _allocPoint) external onlyOwner {
        require(tokenInWhitelist(_token), "Token must be whitelisted");

        totalAllocPoint =
            totalAllocPoint -
            tokens[_token].allocPoint +
            _allocPoint;

        tokens[_token].allocPoint = _allocPoint;
    }

    // Update reward variables of the given token to be up-to-date.
    function updateToken(IERC20 _token)
        public
        returns (TokenInfo memory token)
    {
        require(tokenInWhitelist(_token), "Token must be whitelisted");
        token = tokens[_token];
        if (block.number > token.lastRewardBlock) {
            uint256 tokenSupply = IERC20(_token).balanceOf(address(this));

            if (tokenSupply > 0) {
                uint256 blocksSinceLastReward = block.number -
                    token.lastRewardBlock;

                uint256 dokuReward = (blocksSinceLastReward *
                    dokuPerBlock *
                    token.allocPoint) / totalAllocPoint;

                doku.mint(treasury, (dokuReward * treasuryPercent) / 1000);
                doku.mint(address(this), dokuReward);

                token.accDokuPerShare += (dokuReward * 1e12) / token.amount;
            }

            token.lastRewardBlock = block.number;
            tokens[_token] = token;
        }
    }

    // View function to see pending DOKUs on frontend.
    function pendingDoku(IERC20 _token, address _user)
        external
        view
        returns (uint256)
    {
        require(tokenInWhitelist(_token), "Token must be whitelisted");

        TokenInfo storage token = tokens[_token];
        UserInfo storage user = users[_token][_user];

        uint256 accDokuPerShare = token.accDokuPerShare;
        if (block.number > token.lastRewardBlock && token.amount != 0) {
            uint256 blocksSinceLastReward = block.number -
                token.lastRewardBlock;

            uint256 dokuReward = (blocksSinceLastReward *
                dokuPerBlock *
                token.allocPoint) / totalAllocPoint;

            accDokuPerShare += (dokuReward * 1e12) / token.amount;
        }
        return (user.amount * accDokuPerShare) / 1e12 - user.rewardDebt;
    }

    function massUpdateTokens() public {
        uint256 length = tokenWhitelist.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updateToken(tokenWhitelist[pid]);
        }
    }

    // get tokens given lp consist of
    function getLpTokens(IBalancerPool _lpToken)
        public
        view
        returns (IERC20[] memory tokens_)
    {
        IBalancerVault vault = _lpToken.getVault();
        bytes32 poolId = _lpToken.getPoolId();
        (tokens_, , ) = vault.getPoolTokens(poolId);
    }

    // Deposit tokens to Tsundoku
    function deposit(
        IERC20[] calldata _tokens,
        uint256[] calldata _weights,
        uint256[] calldata _amounts
    ) public {
        require(
            (_tokens.length == _weights.length) &&
                (_weights.length == _amounts.length),
            "Arrays must be same length"
        );

        for (uint256 pid = 0; pid < _tokens.length; ++pid) {
            require(
                tokenInWhitelist(_tokens[pid]),
                "All tokens must be whitelisted"
            );

            IERC20 token_ = _tokens[pid];
            uint256 amount_ = _amounts[pid];

            TokenInfo storage token = tokens[token_];
            UserInfo storage user = users[token_][msg.sender];

            user.amount += amount_;
            user.rewardDebt +=
                (amount_ * token.accDokuPerShare) /
                ACCOUNT_PRECISION;

            token.amount += amount_;

            token_.safeTransferFrom(msg.sender, address(this), amount_);
        }

        router.addLiquidity(_tokens, _weights, _amounts);
    }
}
