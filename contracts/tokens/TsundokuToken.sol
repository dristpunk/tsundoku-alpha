// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "../types/ERC20.sol";
import "../types/Ownable.sol";

contract TsundokuToken is ERC20("TsundokuToken", "DOKU", 18) {
    // todo: change MAX_SUPPLY
    uint256 public constant MAX_SUPPLY = 250_000_000 * 1e18;
    address public farms;

    constructor(address _farms) {
        farms = _farms;
    }

    function mint(address _to, uint256 _amount) public {
        require(msg.sender == farms, "Only farms can mint new tokens");
        require(
            totalSupply + _amount <= MAX_SUPPLY,
            "Cannot exceed max supply"
        );
        _mint(_to, _amount);
    }
}
