// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VotingToken is ERC20 {
    address owner;

    constructor(address owner_) ERC20("Voting Token", "VT") {
        owner = owner_;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Can only execute by owner");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == owner, "Can only execute by owner");
        _burn(from, amount);
    }

    function getTotalSupply() public view returns (uint256) {
        require(msg.sender == owner, "Can only execute by owner");
        return totalSupply();
    }
}