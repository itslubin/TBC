// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExecutableProposal {
    function executeProposal(
        uint256 proposalId,
        uint256 numVotes,
        uint256 numTokens
    ) external payable;
}