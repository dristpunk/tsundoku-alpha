// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./types/Ownable.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IBalancerPool.sol";
import "./interfaces/IBalancerVault.sol";
import "./interfaces/IRouter.sol";
import "./tokens/TsundokuToken.sol";

struct UserInfo {
    IERC20[] tokens; // Tokens user has provided
    mapping(IERC20 => uint256) amounts; // How many tokens user has provided
    uint256 rewardDebt; // reward debt
}

struct TokenInfo {
    uint256 allocPoint;
    uint256 lastRewardBlock; // Last block number that DOKU distribution occurs.
    uint256 accDokuPerShare;
    uint256 amount;
}

contract Farms is Ownable {
    // todo: make events
    // todo: test for user token amount != 0
    // todo: add description to all funcs
    // todo: consider adding router

    using SafeERC20 for IERC20;

    // pools ids
    bytes32[] public poolIds;
    // users info
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // tokens info
    mapping(IERC20 => TokenInfo) public tokenInfo;
    // tsundoku reward token
    TsundokuToken doku;
    // doku reward per 1 block
    uint256 public dokuPerBlock;
    // sum of all allocPoints of all tokens
    uint256 public totalAllocPoint = 0;
    // The block number when DOKU minting starts.
    uint256 public startBlock;
    // Treasury address
    address public treasury;
    // router contract serves to interact with balancer
    IRouter public router;
    // treasury percent from each token reward (1000 = 100%)
    uint256 public treasuryPercent; // 1 decimal
    // allowed tokens to farm
    IERC20[] public tokenWhitelist;
    mapping(IERC20 => bool) public tokenWhitelistMap;
    // constant per precision computations accDokuPerShare
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
        IRouter _router
    ) external onlyOwner {
        require(
            address(doku) == address(0),
            "Farms::Doku address is already set"
        );
        require(
            address(treasury) == address(0),
            "Farms::Treasury address is already set"
        );
        require(
            address(router) == address(0),
            "Farms::Router address is already set"
        );
        doku = _doku;
        treasury = _treasury;
        router = _router;
    }

    function arrayIsSorted(IERC20[] calldata array) public pure returns (bool) {
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

    // Safe DOKU transfer function, just in case if rounding error causes contract to not have enough DOKU
    function safeDokuTransfer(address _to, uint256 _amount) internal {
        uint256 dokuBalance = doku.balanceOf(address(this));
        if (_amount > dokuBalance) {
            doku.transfer(_to, dokuBalance);
        } else {
            doku.transfer(_to, _amount);
        }
    }

    function addToken(IERC20 _token) external onlyOwner {
        tokenWhitelist.push(_token);
        tokenWhitelistMap[_token] = true;
    }

    function removeToken(uint256 _index) external onlyOwner {
        tokenWhitelistMap[tokenWhitelist[_index]] = false;
        tokenWhitelist[_index] = tokenWhitelist[tokenWhitelist.length - 1];
        tokenWhitelist.pop();
    }

    function tokenWhitelistLength() external view returns (uint256) {
        return tokenWhitelist.length;
    }

    function tokenInWhitelist(IERC20 _token) public view returns (bool) {
        return tokenWhitelistMap[_token];
    }

    // update given token info
    function setToken(IERC20 _token, uint256 _allocPoint) external onlyOwner {
        require(tokenInWhitelist(_token), "Farms::Token must be whitelisted");

        totalAllocPoint =
            totalAllocPoint -
            tokenInfo[_token].allocPoint +
            _allocPoint;

        tokenInfo[_token].allocPoint = _allocPoint;
    }

    // create custom pool
    function createPool(
        IERC20[] calldata _tokens,
        uint256[] calldata _weights,
        uint256[] calldata _amounts
    ) external {
        require(
            (_tokens.length == _weights.length) &&
                (_weights.length == _amounts.length),
            "Farms::Arrays must be same length"
        );
        require(arrayIsSorted(_tokens), "Farms::Array must be sorted");

        bytes32 poolId = router.createPool(_tokens, _weights, _amounts);

        poolIds.push(poolId);
    }

    // Update reward variables of the given token to be up-to-date.
    function updateToken(IERC20 _token) public {
        TokenInfo storage token = tokenInfo[_token];

        if (block.number > token.lastRewardBlock) {
            // total amount of such tokens in the contract
            if (token.amount > 0) {
                uint256 blocksSinceLastReward = block.number -
                    token.lastRewardBlock;

                // rewards for this token based on his allocation points
                uint256 dokuRewards = (blocksSinceLastReward *
                    dokuPerBlock *
                    token.allocPoint) / totalAllocPoint;

                doku.mint(address(this), dokuRewards);

                uint256 treasuryRewards = (dokuRewards * treasuryPercent) /
                    1000;

                doku.mint(treasury, treasuryRewards);

                token.accDokuPerShare +=
                    (dokuRewards * ACCOUNT_PRECISION) /
                    token.amount;
            }
            token.lastRewardBlock = block.number;
        }
    }

    // View function to see pending DOKU on frontend.
    function pendingDoku(uint256 _pid, address _user)
        external
        view
        returns (uint256 pending)
    {
        UserInfo storage user = userInfo[_pid][_user];

        for (uint256 i = 0; i < user.tokens.length; ++i) {
            TokenInfo memory token = tokenInfo[user.tokens[i]];
            IERC20 token_ = user.tokens[i];

            uint256 blocksSinceLastReward = block.number -
                token.lastRewardBlock;
            // based on the token weight (allocation points) we calculate the doku rewarded for this specific token
            uint256 dokusRewards = (blocksSinceLastReward *
                dokuPerBlock *
                token.allocPoint) / totalAllocPoint;

            // we calculate the new amount of accumulated doku per for token
            uint256 accDokuPerShare = token.accDokuPerShare;

            // token amount can't be eq 0
            accDokuPerShare += ((dokusRewards * ACCOUNT_PRECISION) /
                token.amount);

            // resulting pool reward is sum of tokens rewards
            pending += (user.amounts[token_] * accDokuPerShare);
        }
        // dont forget to divide back
        pending /= ACCOUNT_PRECISION;
        // dont forget to sub users rewardDebt of the pool
        pending -= user.rewardDebt;
    }

    function massUpdateTokens() public {
        uint256 length = tokenWhitelist.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updateToken(tokenWhitelist[pid]);
        }
    }

    // get tokens given lp consist of
    // todo: delete
    function getLpTokens(IBalancerPool _lpToken)
        public
        view
        returns (IERC20[] memory tokens_)
    {
        IBalancerVault vault = _lpToken.getVault();
        bytes32 poolId = _lpToken.getPoolId();
        (tokens_, , ) = vault.getPoolTokens(poolId);
    }

    // Deposit tokens to existing pool
    function deposit(
        uint256 _pid,
        IERC20[] calldata _tokens,
        uint256[] calldata _amounts,
        address _to
    ) public {
        require(
            (_tokens.length == _amounts.length),
            "Farms::Arrays must be same length"
        );

        require(arrayIsSorted(_tokens), "Farms::Array must be sorted");

        UserInfo storage user = userInfo[_pid][_to];

        for (uint256 i = 0; i < _tokens.length; ++i) {
            require(
                tokenInWhitelist(_tokens[i]),
                "Farms::All tokens must be whitelisted"
            );

            IERC20 token_ = _tokens[i];
            uint256 amount_ = _amounts[i];

            updateToken(token_);

            TokenInfo storage token = tokenInfo[token_];

            if (user.amounts[token_] == 0) {
                user.tokens.push(token_);
            }
            user.amounts[token_] += amount_;

            user.rewardDebt +=
                (amount_ * token.accDokuPerShare) /
                ACCOUNT_PRECISION;

            token.amount += amount_;

            token_.safeTransferFrom(msg.sender, address(router), amount_);
        }

        router.addLiquidity(poolIds[_pid], _tokens, _amounts);
    }

    function harvest(uint256 _pid, address _to) public {
        UserInfo storage user = userInfo[_pid][msg.sender];

        // this would  be the amount if the user joined right from the start of the farm
        uint256 accumulatedDoku;

        for (uint256 i = 0; i < user.tokens.length; ++i) {
            IERC20 token_ = user.tokens[i];

            updateToken(token_);

            TokenInfo memory token = tokenInfo[token_];

            // resulting amount is sum over all tokens
            accumulatedDoku += user.amounts[token_] * token.accDokuPerShare;
        }
        // subtracting the rewards the user is not eligible for
        uint256 eligibleDoku = (accumulatedDoku / ACCOUNT_PRECISION) -
            user.rewardDebt;

        // we set the new rewardDebt to the current accumulated amount of rewards
        user.rewardDebt = accumulatedDoku;

        if (eligibleDoku > 0) {
            safeDokuTransfer(_to, eligibleDoku);
        }
    }

    function harvestAll(uint256[] calldata _pids, address _to) external {
        for (uint256 i = 0; i < _pids.length; i++) {
            harvest(_pids[i], _to);
        }
    }

    function withdrawAndHarvest(
        uint256 _pid,
        IERC20[] calldata _tokens,
        uint256[] calldata _amounts,
        address _to
    ) public {
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(
            (_tokens.length == _amounts.length),
            "Farms::Arrays must be same length"
        );

        require(arrayIsSorted(_tokens), "Farms::Array must be sorted");

        uint256 accumulatedBeets;
        uint256 rewardDebtDecay;

        router.removeLiquidity(poolIds[_pid], _tokens, _amounts);

        for (uint256 i = 0; i < _tokens.length; ++i) {
            IERC20 token_ = _tokens[i];
            uint256 amount_ = _amounts[i];

            require(
                amount_ <= user.amounts[token_],
                "Farms::Cannot withdraw more than deposited"
            );

            updateToken(token_);

            TokenInfo storage token = tokenInfo[token_];

            // this would  be the amount if the user joined right from the start of the farm
            accumulatedBeets += user.amounts[token_] * token.accDokuPerShare;

            rewardDebtDecay += amount_ * token.accDokuPerShare;

            user.amounts[token_] -= amount_;
            token.amount -= amount_;

            token_.safeTransfer(_to, amount_);
        }
        uint256 eligibleBeets = (accumulatedBeets / ACCOUNT_PRECISION) -
            user.rewardDebt;

        /*
        after harvest & withdraw, he should be eligible for exactly 0 tokens
        => userInfo.amount * pool.accBeetsPerShare / ACC_BEETS_PRECISION == userInfo.rewardDebt
        since we are removing some LP's from userInfo.amount, we also have to remove
        the equivalent amount of reward debt
        */
        user.rewardDebt =
            accumulatedBeets -
            (rewardDebtDecay / ACCOUNT_PRECISION);

        safeDokuTransfer(_to, eligibleBeets);
    }
}
