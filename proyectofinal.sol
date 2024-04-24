// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IExecutableProposal {
    function executeProposal(uint proposalId, uint numVotes, uint numTokens) external payable;
}

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

contract QuadraticVoting {
    struct Proposal {
        address owner;
        string title;
        string description;
        uint budget;
        uint numVotes;
        address executableContract;
        mapping(address => uint) votesRecord;
        address[] voters;
        bool approved;
        bool cancelled;
    }

    address owner;
    bool public votingOpen;
    uint public totalBudget;
    uint public numToken;
    uint public tokenPrice;

    uint public participantCounter;
    uint public proposalCounter;

    VotingToken public token;
    address[] public participants;
    uint[] pendingProposals;
    uint[] approvedProposals;
    mapping(uint => Proposal) public proposals;

    constructor(uint _tokenPrice, uint _numToken) {
        token = new VotingToken(msg.sender);
        tokenPrice = _tokenPrice;
        numToken = _numToken;
        owner = msg.sender;
        proposalCounter = 0;
        participantCounter = 0;
    }

    function openVoting(uint initialBudget) external {
        require(!votingOpen, "Voting already open");
        require(owner == msg.sender, "Only execute by contract owner");
        totalBudget = initialBudget;
        votingOpen = true;
    }

    function addParticipant() external payable {
        require(msg.value >= tokenPrice, "At least buy one token");
        for (uint i = 0; i < participants.length; i++) {
            require(participants[i] != msg.sender, "Participant already exists");
        }
        uint tokensToMint = msg.value;
        token.mint(msg.sender, tokensToMint);
        
        participantCounter++;
    }

    function removeParticipant() external {
        bool isFound = false;
        for (uint i = 0; i < participants.length; i++) {
            if (participants[i] == msg.sender) {
                participants[i] = participants[participants.length - 1];
                participants.pop();
                isFound = true;
            }
        }
        require(isFound, "Participant not found");
        payable(msg.sender).transfer(token.balanceOf(msg.sender) * tokenPrice);
        token.burn(msg.sender, token.balanceOf(msg.sender));
    }

    function addProposal(string memory title, string memory description, uint budget, address executableContract) external {
        require(votingOpen, "Voting not open");
        Proposal storage p = proposals[proposalCounter];
        p.title = title;
        p.description = description;
        p.budget = budget;
        p.executableContract = executableContract;
        p.approved = false;
        p.cancelled = false;
        pendingProposals.push(proposalCounter++);
    }

    function cancelProposal(uint proposalId) external {
        require(votingOpen, "Voting not open");
        require(!proposals[proposalId].approved, "Proposal already approved");
        for (uint i = 0; i < pendingProposals.length; i++) {
            if (pendingProposals[i] == proposalId) {
                pendingProposals[i] =  pendingProposals[pendingProposals.length - 1];
            }
        }
        pendingProposals.pop();

        Proposal storage p = proposals[proposalId];
        for (uint i = 0; i < p.voters.length; i++) {
            token.mint(p.voters[i], p.votesRecord[p.voters[i]]);
        }
    }

    function buyTokens() external payable {
        uint tokensToMint = msg.value / tokenPrice;
        require(token.getTotalSupply() + tokensToMint <= numToken, "There is no more token");
        uint rest = msg.value % tokenPrice;
        token.mint(msg.sender, tokensToMint);
        if (rest > 0)
            payable(msg.sender).transfer(rest);
    }

    function sellTokens(uint amount) external {
        require(token.balanceOf(msg.sender) >= amount, "Not enough tokens");
        token.burn(msg.sender, amount);
        payable(msg.sender).transfer(amount * tokenPrice);
    }

    function getERC20() public view returns (address) {
        return address(token);
    }

    function getPendingProposals() public view returns (uint[] memory) {
        return pendingProposals;
    }

    function getApprovedProposals() public view returns (uint[] memory) {
        return approvedProposals;
    }

    function getSignalingProposals() public view returns (uint[] memory) {
        uint[] memory signalingProposals = new uint[](pendingProposals.length);
        uint counter = 0;
        for (uint i = 0; i < pendingProposals.length; i++) {
            uint id = pendingProposals[i];
            if (proposals[id].budget == 0) {
                signalingProposals[counter++] = id;
            }
        }
        return signalingProposals;
    }

    function getProposalInfo(uint proposalId) public view returns (string memory title, string memory description, uint budget, address executableContract, uint numVotes, bool approved) {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.title, proposal.description, proposal.budget, proposal.executableContract, proposal.numVotes, proposal.approved);
    }

    function stake(uint proposalId, uint numVotes) external {
        require(votingOpen, "Voting not open");
        uint currentVotes = proposals[proposalId].votesRecord[msg.sender];
        if (currentVotes == 0) {
            proposals[proposalId].voters.push(msg.sender);
        }
        uint newVotes = currentVotes + numVotes;
        uint cost = newVotes * newVotes - currentVotes * currentVotes;

        require(token.balanceOf(msg.sender) >= cost, "Insufficient tokens");
        proposals[proposalId].numVotes += numVotes;
        proposals[proposalId].votesRecord[msg.sender] = newVotes;
        token.transferFrom(msg.sender, address(this), cost);
        totalBudget += cost * tokenPrice;
        _checkAndExecuteProposal(proposalId);
    }

    function withdrawFromProposal(uint proposalId, uint numVotes) external {
        require(votingOpen, "Voting not open");
        require(!proposals[proposalId].approved, "This proposal has been approved.");
        uint currentVotes = proposals[proposalId].votesRecord[msg.sender];
        require(currentVotes >= numVotes, "");

        uint newVotes = currentVotes - numVotes;
        proposals[proposalId].numVotes -= numVotes;
        uint tokensToReturn = currentVotes * currentVotes - newVotes * newVotes;
        totalBudget -= tokensToReturn * tokenPrice;
        token.transferFrom(address(this), msg.sender, tokensToReturn);
    }

    function _checkAndExecuteProposal(uint proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        uint threshold = (2 + 10 * proposal.budget / totalBudget) * participants.length / 10 + pendingProposals.length;
        if (proposal.numVotes > threshold && proposal.budget > 0 && proposal.budget <= proposal.numVotes * tokenPrice) {
            IExecutableProposal(proposal.executableContract).executeProposal{value: proposal.budget}(proposalId, proposal.numVotes, proposal.numVotes * proposal.numVotes);
            proposal.approved = true;
            for (uint i = 0; i < pendingProposals.length; i++) {
                if (pendingProposals[i] == proposalId) {
                    pendingProposals[i] = pendingProposals[pendingProposals.length - 1];
                    approvedProposals.push(proposalId);
                }
            }
            totalBudget -= proposal.budget;
        }
    }

    function closeVoting() external {
        require(votingOpen, "Voting not open");
        votingOpen = false;
        // Return tokens for all non-approved proposals
        for (uint i = 0; i < pendingProposals.length; i++) {
            Proposal storage p = proposals[pendingProposals[i]];
            for (uint j = 0; j < p.voters.length; j++) {
                token.transferFrom(address(this), p.voters[j], p.votesRecord[p.voters[j]]);
            }
        }
        payable(owner).transfer(totalBudget);
    }
}
