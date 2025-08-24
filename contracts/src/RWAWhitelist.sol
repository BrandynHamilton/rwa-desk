// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";

contract WhitelistRegistry is Ownable {
    mapping(address => bool) public whitelisted;

    event Whitelisted(address indexed user);
    event RemovedFromWhitelist(address indexed user);

    constructor() Ownable(msg.sender) {}

    /// @notice Add address to whitelist
    function addToWhitelist(address user) external onlyOwner {
        whitelisted[user] = true;
        emit Whitelisted(user);
    }

    /// @notice Remove address from whitelist
    function removeFromWhitelist(address user) external onlyOwner {
        whitelisted[user] = false;
        emit RemovedFromWhitelist(user);
    }

    /// @notice Check if address is whitelisted
    function isWhitelisted(address user) external view returns (bool) {
        return whitelisted[user];
    }
}
