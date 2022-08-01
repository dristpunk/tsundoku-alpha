// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "../types/Ownable.sol";
import "../libraries/SafeERC20.sol";
import "../interfaces/IERC20Metadata.sol";
import "../tokens/TsundokuToken.sol";

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
    mapping(address => mapping(address => UserInfo)) public users;
    // tokens info
    mapping(address => TokenInfo) public tokens;
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
    // treasury percent from each token reward (1000 = 100%)
    uint256 public treasuryPercent; // 1 decimal
    // allowed token to farm
    address[] public tokenWhitelist;
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

    function initialize(TsundokuToken _doku, address _treasury)
        external
        onlyOwner
    {
        require(address(doku) == address(0), "Doku address already set");
        require(
            address(treasury) == address(0),
            "Treasury address already set"
        );
        doku = _doku;
        treasury = _treasury;
    }

    function addToken(address _token) external onlyOwner {
        tokenWhitelist.push(_token);
    }

    function removeToken(uint256 _index) external onlyOwner {
        tokenWhitelist[_index] = tokenWhitelist[tokenWhitelist.length - 1];
        tokenWhitelist.pop();
    }

    function tokenWhitelistLength() external view returns (uint256) {
        return tokenWhitelist.length;
    }

    // update given token info
    function setToken(address _token, uint256 _allocPoint) external onlyOwner {
        // todo: whitelist checks

        totalAllocPoint =
            totalAllocPoint -
            tokens[_token].allocPoint +
            _allocPoint;

        tokens[_token].allocPoint = _allocPoint;
    }

    // Update reward variables of the given token to be up-to-date.
    function updateToken(address _token) public {
        TokenInfo storage token = tokens[_token];
        if (block.number <= token.lastRewardBlock) {
            return;
        }

        uint256 tokenSupply = IERC20(_token).balanceOf(address(this));

        if (tokenSupply == 0) {
            token.lastRewardBlock = block.number;
            return;
        }

        uint256 blocksSinceLastReward = block.number - token.lastRewardBlock;

        uint256 dokuReward = (blocksSinceLastReward *
            dokuPerBlock *
            token.allocPoint) / totalAllocPoint;

        doku.mint(treasury, (dokuReward * treasuryPercent) / 1000);

        token.accDokuPerShare += (dokuReward * 1e12) / token.amount;
        token.lastRewardBlock = block.number;
    }

    // View function to see pending DOKUs on frontend.
    function pendingDoku(address _token, address _user)
        external
        view
        returns (uint256)
    {
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

    // Deposit LP tokens to MasterChef for CAKE allocation.
    function deposit(address _lpToken, uint256 _amount) public {
        // todo: deposit multiply lptokens
        // PoolInfo storage pool = poolInfo[_pid];
        // UserInfo storage user = userInfo[_pid][msg.sender];
        // updatePool(_pid);
        // if (user.amount > 0) {
        //     uint256 pending = user.amount.mul(pool.accCakePerShare).div(1e12).sub(user.rewardDebt);
        //     if (pending > 0) {
        //         safeCakeTransfer(msg.sender, pending);
        //     }
        // }
        // if (_amount > 0) {
        //     pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        //     user.amount = user.amount.add(_amount);
        // }
        // user.rewardDebt = user.amount.mul(pool.accCakePerShare).div(1e12);
        // emit Deposit(msg.sender, _pid, _amount);
    }
}
