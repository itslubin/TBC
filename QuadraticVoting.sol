// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./VotingToken.sol";
import "./IExecutableProposal.sol";

contract QuadraticVoting {
    // Estructura para almacenar información de una propuesta
    struct Proposal {
        address owner;
        string title;
        string description;
        uint256 budget;
        uint256 numVotes;
        uint256 numTokens;
        address executableContract;
        mapping(address => uint256) votesRecord; // Registro de los votos de cada usuario en la propuesta
        address[] voters;
        bool approved;
        bool cancelled;
    }

    // Variables de estado
    address owner;
    bool public votingOpen;
    uint256 public totalBudget;
    uint256 public numToken;
    uint256 public tokenPrice;
    uint256 public numParticipant;
    uint256 public proposalCounter;

    // Contrato ERC20 para tokens de votación
    VotingToken public token;

    // Mapa para registrar participantes
    mapping(address => bool) public participants;

    // Array de propuestas pendientes
    uint256[] pendingProposals;

    // Array de propuestas aprobadas
    uint256[] approvedProposals;

    // Array para las propuestas de signaling
    uint256[] signalingProposals;

    // Mapa de propuestas
    mapping(uint256 => Proposal) public proposals;

    // Modificador para permitir solo al propietario del contrato ejecutar una función
    modifier onlyOwner() {
        require(msg.sender == owner, "Only executable by contract owner");
        _;
    }

    // Modificador para verificar si la votación está abierta
    modifier votingIsOpen() {
        require(votingOpen, "Voting is not open");
        _;
    }

    // Modificador para verificar si la votación está cerrada
    modifier votingIsClosed() {
        require(!votingOpen, "Voting is still open");
        _;
    }

    // Constructor del contrato
    constructor(uint256 _tokenPrice, uint256 _numToken) {
        token = new VotingToken(address(this));
        tokenPrice = _tokenPrice;
        numToken = _numToken;
        owner = msg.sender;
        proposalCounter = 0;
        numParticipant = 0;
    }

    // Función para abrir la votación
    function openVoting()
        external
        payable
        onlyOwner
        votingIsClosed
    {
        totalBudget = msg.value;
        votingOpen = true;

        // Inicialización
        proposalCounter = 0;
        delete pendingProposals;
        delete approvedProposals;
        delete signalingProposals;
    }

    // Función para agregar un participante
    function addParticipant() external payable {
        require(msg.value >= tokenPrice, "At least buy one token");
        require(!participants[msg.sender], "Participant already exists");

        participants[msg.sender] = true;
        numParticipant++;

        buyTokens();
    }

    // Función para eliminar un participante
    function removeParticipant() external {
        require(participants[msg.sender], "Participant not found");
        uint balan = token.balanceOf(msg.sender);
        token.burn(msg.sender, balan);
        payable(msg.sender).transfer(balan * tokenPrice);

        delete participants[msg.sender];
        numParticipant--;
    }

    // Función para agregar una propuesta
    function addProposal(
        string memory title,
        string memory description,
        uint256 budget,
        address executableContract
    ) external votingIsOpen returns (uint256) {
        require(participants[msg.sender], "You are not a participant");
        Proposal storage p = proposals[proposalCounter];

        if (budget == 0) { // Guardamos la id de la propuesta de signaling
            signalingProposals.push(proposalCounter);
        }

        p.owner = msg.sender;
        p.title = title;
        p.description = description;
        p.budget = budget;
        p.numVotes = 0;
        p.numTokens = 0;
        p.executableContract = executableContract;
        p.approved = false;
        p.cancelled = false;

        // Eliminar posible voterRecords del proposal anterior
        uint len = p.voters.length;
        for (uint i = 0; i < len; i++) {
            delete p.votesRecord[p.voters[i]];
        }
        delete p.voters;

        pendingProposals.push(proposalCounter);

        return proposalCounter++;
    }

    // Función para cancelar una propuesta
    function cancelProposal(uint256 proposalId) external votingIsOpen {
        require(proposalId < proposalCounter, "Proposal does not exist");
        require(!proposals[proposalId].approved, "Proposal already approved");
        require(!proposals[proposalId].cancelled, "Proposal already cancelled");
        require(
            proposals[proposalId].owner == msg.sender,
            "You are not the proposal owner"
        );

        uint256 len = pendingProposals.length;
        for (uint256 i = 0; i < len; i++) {
            if (pendingProposals[i] == proposalId) {
                pendingProposals[i] = pendingProposals[len - 1];
                break;
            }
        }
        pendingProposals.pop();

        if (proposals[proposalId].budget == 0) { // Si la propuesta es de signaling
            uint len1 = signalingProposals.length;
            for (uint i = 0; i < len1; ++i) {
                if (signalingProposals[i] == proposalId) {
                    signalingProposals[i] = signalingProposals[len - 1];
                    break;
                }
            }
            pendingProposals.pop();
        }

        Proposal storage p = proposals[proposalId];
        uint256 vlen = p.voters.length;
        for (uint256 i = 0; i < vlen; i++) {
            token.transfer(p.voters[i], p.votesRecord[p.voters[i]]);
        }

        proposals[proposalId].cancelled = true;
    }

    // Función para comprar tokens
    function buyTokens() public payable {
        require(participants[msg.sender], "You are not a participant yet");
        uint256 tokensToMint = msg.value / tokenPrice;
        require(
            token.getTotalSupply() + tokensToMint <= numToken,
            "There is no more token available to mint"
        );
        uint256 rest = msg.value % tokenPrice;
        token.mint(msg.sender, tokensToMint);
        if (rest > 0) payable(msg.sender).transfer(rest);
    }

    // Función para vender tokens
    function sellTokens(uint256 amount) external {
        // pull over push
        require(token.balanceOf(msg.sender) >= amount, "Not enough tokens");
        token.burn(msg.sender, amount);
        payable(msg.sender).transfer(amount * tokenPrice);
    }

    // Función para obtener la dirección del contrato ERC20
    function getERC20() public view returns (address) {
        return address(token);
    }

    // Función para obtener las propuestas pendientes
    function getPendingProposals() public view returns (uint256[] memory) {
        return pendingProposals;
    }

    // Función para obtener las propuestas aprobadas
    function getApprovedProposals() public view returns (uint256[] memory) {
        return approvedProposals;
    }

    // Función para obtener las propuestas de señalización
    function getSignalingProposals() public view returns (uint256[] memory) {
        /* uint256 len = pendingProposals.length;
        uint256[] memory signalingProposals = new uint256[](len);
        uint256 counter = 0;
        for (uint256 i = 0; i < len; i++) {
            uint256 id = pendingProposals[i];
            if (proposals[id].budget == 0) {
                signalingProposals[counter++] = id;
            }
        } */
        return signalingProposals;
    }

    // Función para obtener información de una propuesta
    function getProposalInfo(uint256 proposalId)
        public
        view
        returns (
            string memory title,
            string memory description,
            uint256 budget,
            address executableContract,
            uint256 numVotes,
            uint256 numTokens,
            bool approved,
            bool cancelled
        )
    {
        require(proposalId < proposalCounter, "Proposal does not exist");
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.title,
            proposal.description,
            proposal.budget,
            proposal.executableContract,
            proposal.numVotes,
            proposal.numTokens,
            proposal.approved,
            proposal.cancelled
        );
    }

    // Función para votar en una propuesta
    function stake(uint256 proposalId, uint256 numVotes) external votingIsOpen {
        require(proposalId < proposalCounter, "Proposal does not exist");
        require(!proposals[proposalId].approved, "Proposal has been approved");
        require(
            !proposals[proposalId].cancelled,
            "Proposal has been cancelled"
        );

        uint256 currentVotes = proposals[proposalId].votesRecord[msg.sender];
        if (currentVotes == 0) {
            proposals[proposalId].voters.push(msg.sender);
        }
        uint256 newVotes = currentVotes + numVotes;
        uint256 cost = newVotes * newVotes - currentVotes * currentVotes;

        // Verificar si el participante ha aprobado el gasto de tokens al contrato de votación
        require(
            token.allowance(msg.sender, address(this)) >= cost,
            "Insufficient allowance"
        );

        // Transferir los tokens desde el participante al contrato de votación
        token.transferFrom(msg.sender, address(this), cost);

        // Actualizar el estado de la propuesta
        proposals[proposalId].numTokens += cost;
        proposals[proposalId].numVotes += numVotes;
        proposals[proposalId].votesRecord[msg.sender] = newVotes;

        if (proposals[proposalId].budget > 0) {
            totalBudget += cost * tokenPrice;
            _checkAndExecuteProposal(proposalId);
        }
    }

    // Función para retirar votos de una propuesta
    function withdrawFromProposal(uint256 proposalId, uint256 numVotes)
        external
        votingIsOpen
    {
        require(proposalId < proposalCounter, "Proposal does not exist");
        require(!proposals[proposalId].approved, "Proposal has been approved");
        require(!proposals[proposalId].cancelled, "Proposal has been cancelled");

        uint256 currentVotes = proposals[proposalId].votesRecord[msg.sender];
        require(currentVotes >= numVotes, "Not enough votes");

        uint256 newVotes = currentVotes - numVotes;
        uint256 tokensToReturn = currentVotes ** 2 - newVotes ** 2;

        // Si el votante tiene 0 votos en la propuesta, borrarlo de la lista de votantes de la propuesta
        Proposal storage prop = proposals[proposalId];
        if (newVotes == 0) {
            uint len = prop.voters.length;
            for (uint i = 0; i < len; i++) {
                if (prop.voters[i] == msg.sender) {
                    prop.voters[i] = prop.voters[len - 1];
                    break;
                }
            }
        }

        prop.numVotes -= numVotes;
        prop.numTokens -= tokensToReturn;
        if (prop.budget > 0) {
            totalBudget -= tokensToReturn * tokenPrice;
        }
        token.transfer(msg.sender, tokensToReturn);
    }

    // Función interna para verificar y ejecutar una propuesta
    function _checkAndExecuteProposal(uint256 proposalId) internal {
        uint256 len = pendingProposals.length;
        Proposal storage proposal = proposals[proposalId];
        uint256 threshold = ((2 + (10 * proposal.budget) / totalBudget) *
            numParticipant) /
            10 +
            len;
        if (
            proposal.numVotes > threshold ||
            (proposal.budget > 0 && proposal.budget <= proposal.numTokens * tokenPrice)
        ) {
            IExecutableProposal(proposal.executableContract).executeProposal{
                value: proposal.budget
            }(
                proposalId,
                proposal.numVotes,
                proposal.numTokens
            );
            proposal.approved = true;

            for (uint256 i = 0; i < len; i++) {
                if (pendingProposals[i] == proposalId) {
                    pendingProposals[i] = pendingProposals[len - 1]; // eliminamos la propuesta de las pendientes
                    approvedProposals.push(proposalId); //añadimos a la lista de propuestas aprovadas
                    break;
                }
            }

            pendingProposals.pop();

            totalBudget -= proposal.budget;
        }
    }

    // Función para cerrar la votación
    function closeVoting() external onlyOwner votingIsOpen {
        votingOpen = false;
    }

    function withdrawOwner() external onlyOwner votingIsClosed {
        // El presupuesto de la votación no gastado en las propuestas se transfiere al propietario del contrato de votación
        payable(owner).transfer(totalBudget);
    }

    // Parte opcional: cada participante extrae sus tokens -> AllowForPull
    function withdrawTokens() external votingIsClosed {
        uint256 value = 0;
        uint256 len = pendingProposals.length;
        for (uint256 i = 0; i < len; i++) {
            value += proposals[pendingProposals[i]].votesRecord[msg.sender]**2;
            proposals[pendingProposals[i]].votesRecord[msg.sender] = 0;
        }
        token.transfer(msg.sender, value);
    }

    // Parte opcional: cada propietario del signaling proposal execute sus proposal
    function executeSignalingProposal(uint256 proposalId) external votingIsClosed {
        require(proposalId < proposalCounter, "Proposal does not exist");

        Proposal storage prop = proposals[proposalId];
        require(!prop.approved, "Proposal has been executed");
        require(!prop.cancelled, "Proposal already cancelled");
        require(prop.budget == 0, "Proposal is not a signaling proposal");
        require(prop.owner == msg.sender, "You are not the proposal owner");

        IExecutableProposal(prop.executableContract).executeProposal{value: 0}(
            proposalId,
            prop.numVotes,
            prop.numTokens
        );
        prop.approved = true;
    }
}