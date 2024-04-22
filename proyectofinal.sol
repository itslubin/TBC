// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IExecutableProposal {
    function executeProposal(uint proposalId, uint numVotes, uint numTokens) external payable;
}

contract VotingToken is ERC20 {
    constructor() ERC20("Voting Token", "VT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract QuadraticVoting {
    struct Proposal {
        string title;
        string description;
        uint budget;
        address executableContract;
        uint numVotes;
        bool approved;
    }

    address owner;
    bool public votingOpen;
    uint public totalBudget;
    uint public tokenPrice;
    uint public numToken;
    uint public numParticipants;
    uint public numPendingProposal;
    uint public ParticipantCounter;

    VotingToken public token;
    mapping(uint => Proposal) public proposals;

    mapping(address => uint) public tokensSpent;
    uint public proposalCount;

    constructor(uint _tokenPrice, uint _numToken) {
        token = new VotingToken();
        tokenPrice = _tokenPrice;
        numToken = _numToken;
        owner = msg.sender;
    }

    function openVoting(uint initialBudget) external {
        require(!votingOpen, "Voting already open");
        require(owner == msg.sender, "Only execute by contract owner");
        totalBudget = initialBudget;
        votingOpen = true;
    }

    function addParticipant() external payable {
        require(msg.value >= tokenPrice, "At least buy one token");
        uint tokensToMint = msg.value;
        token.mint(msg.sender, tokensToMint);
        ParticipantCounter++;
    }

    function removeParticipant() external {
        token.burn(msg.sender, token.balanceOf(msg.sender));
    }

    function addProposal(string memory title, string memory description, uint budget, address executableContract) external {
        require(votingOpen, "Voting not open");
        proposals[proposalCount++] = Proposal(title, description, budget, executableContract, 0, false);
    }

    function cancelProposal(uint proposalId) external {
        require(msg.sender == owner, "Only owner can cancel proposals");
        require(votingOpen, "Voting not open");
        require(!proposals[proposalId].approved, "Proposal already approved");
        token.burn(address(this), tokensSpent[msg.sender]);
    }

    function buyTokens() external payable {
        uint tokensToMint = msg.value; // Assume 1 ETH = 1 token for simplicity
        token.mint(msg.sender, tokensToMint);
    }

    function sellTokens(uint amount) external {
        require(token.balanceOf(msg.sender) >= amount, "Not enough tokens");
        token.burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    function getERC20() public view returns (address) {
        return address(token);
    }

    function getPendingProposals() public view returns (uint[] memory) {
        uint[] memory pendingProposals = new uint[](proposalCount);
        uint counter = 0;
        for (uint i = 0; i < proposalCount; i++) {
            if (!proposals[i].approved && proposals[i].budget > 0) {
                pendingProposals[counter++] = i;
            }
        }
        return pendingProposals;
    }

    function getApprovedProposals() public view returns (uint[] memory) {
        uint[] memory approvedProposals = new uint[](proposalCount);
        uint counter = 0;
        for (uint i = 0; i < proposalCount; i++) {
            if (proposals[i].approved) {
                approvedProposals[counter++] = i;
            }
        }
        return approvedProposals;
    }

    function getSignalingProposals() public view returns (uint[] memory) {
        uint[] memory signalingProposals = new uint[](proposalCount);
        uint counter = 0;
        for (uint i = 0; i < proposalCount; i++) {
            if (proposals[i].budget == 0) {
                signalingProposals[counter++] = i;
            }
        }
        return signalingProposals;
    }

    function getProposalInfo(uint proposalId) public view returns (string memory title, string memory description, uint budget, address executableContract, uint numVotes, bool approved) {
        Proposal memory proposal = proposals[proposalId];
        return (proposal.title, proposal.description, proposal.budget, proposal.executableContract, proposal.numVotes, proposal.approved);
    }

    function stake(uint proposalId, uint numVotes) external {
        uint cost = numVotes * numVotes; // Quadratic cost
        require(token.balanceOf(msg.sender) >= cost, "Insufficient tokens");
        proposals[proposalId].numVotes += numVotes;
        tokensSpent[msg.sender] += cost;
        token.transferFrom(msg.sender, address(this), cost);
        _checkAndExecuteProposal(proposalId);
    }

    function withdrawFromProposal(uint proposalId, uint numVotes) external {
        require(tokensSpent[msg.sender] >= numVotes * numVotes, "Not enough votes cast");
        proposals[proposalId].numVotes -= numVotes;
        uint tokensToReturn = numVotes * numVotes;
        tokensSpent[msg.sender] -= tokensToReturn;
        token.transfer(msg.sender, tokensToReturn);
    }

    function _checkAndExecuteProposal(uint proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        uint threshold = (2 + 10 * proposal.budget / totalBudget) * ParticipantCounter / 10 + proposalCount;
        if (proposal.numVotes > threshold && proposal.budget <= totalBudget) {
            IExecutableProposal(proposal.executableContract).executeProposal{value: proposal.budget}(proposalId, proposal.numVotes, tokensSpent[msg.sender]);
            proposal.approved = true;
            totalBudget -= proposal.budget;
            token.burn(address(this), tokensSpent[msg.sender]);
        }
    }

    function closeVoting() external {
        require(votingOpen, "Voting not open");
        votingOpen = false;
        // Return tokens for all non-approved proposals
        for (uint i = 0; i < proposalCount; i++) {
            if (!proposals[i].approved) {
                token.transfer(proposals[i].executableContract, tokensSpent[msg.sender]);
            }
        }
        payable(owner).transfer(totalBudget);
    }
}
