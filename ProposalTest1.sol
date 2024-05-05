// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IExecutableProposal.sol";

contract Proposal is IExecutableProposal {
    
    uint budget;

    event ProposalExecuted(uint256 indexed proposalId, uint256 numVotes, uint256 numTokens);

    constructor(uint _budget) {
        budget = _budget;
    }

    function executeProposal(uint256 proposalId, uint256 numVotes,uint256 numTokens) external payable {
        require(msg.value == budget, "Not enough budget");

        // Hacer cosas ...

        emit ProposalExecuted(proposalId, numVotes, numTokens);
    }
}