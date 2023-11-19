// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./GovernanceNFT.sol";

/** 
GoverningBoard should: 
- allow BoardMembers to vote, create and execute proposals 
- allow contract owner to veto a proposal
*/

contract GoverningBoard is Ownable {
    GovernanceNFT private governanceNFT;
    uint public minVotesThreshhold; //where 1e4 means 100%, 1% = 1e2

    enum ProposalStatus {
        active, //if active you can vote on it.
        passed, //if passed it can be executed
        executed, //already executed
        vetoed, //was vetoed by admin
        expired // voting not up to min threshold before deadline passed
    }

    struct Proposal {
        address proposer;
        address proposalTarget;
        bytes proposalTxData;
        uint40 proposalDeadline; // check that proposal deadline must be >= now when making proposals.
        uint40 timeOfExecution;
        bool vetoed;
    }

    mapping(bytes32 => Proposal) private ProposalsMapping;
    mapping(bytes32 => uint) private VoteCount;
    mapping(bytes32 => mapping(address => bool)) public BoardMemberVoted;

    event Proposed(bytes32 proposalID, uint currentTimeStamp);
    event Voted(address voter, uint votes, bytes32 proposalID);
    event Executed(bytes32 proposalID, uint time);
    event Vetoed(bytes32 proposalID);
    event ReceivedEther(uint value, address sender);

    error InvalidDeadline();
    error InvalidTimeOfExecution();
    error InvalidProposal();
    error InvalidVoter();
    error InvalidVotingPower();
    error NotEnoughVotes();
    error AlreadyProposed();

    constructor(
        GovernanceNFT _governanceNFT,
        uint _minVotesThreshhold
    ) Ownable(msg.sender) {
        require(
            minVotesThreshhold >= 1e2 && minVotesThreshhold <= 1e4,
            "invalid votes threshold"
        );
        governanceNFT = _governanceNFT;
        minVotesThreshhold = _minVotesThreshhold;
    }

    function propose(
        Proposal memory _proposal,
        uint40 tokenID
    ) external returns (bytes32) {
        //to vote you must be an nft holder.
        if (_proposal.proposalDeadline < block.timestamp)
            revert InvalidDeadline();
        if (_proposal.timeOfExecution != 0) revert InvalidTimeOfExecution();

        // add new proposal to proposals mapping
        bytes32 proposalID = keccak256(
            abi.encode(
                _proposal.proposalTarget,
                _proposal.proposalDeadline,
                _proposal.proposalTxData,
                _proposal.proposer,
                msg.sender
            )
        );

        //cant propose already proposed proposal
        if (ProposalsMapping[proposalID].proposalDeadline > 0)
            revert AlreadyProposed();

        //add proposal to mapping
        ProposalsMapping[proposalID] = _proposal;

        //the proposer must vote on his proposal.
        vote(proposalID, tokenID, governanceNFT.VotingPower(tokenID));

        emit Proposed(proposalID, block.timestamp);
        return proposalID;
    }

    function vote(bytes32 _proposalID, uint tokenID, uint numOfVotes) public {
        //check that proposal is not vetoed, expired or executed and check that user has not voted on the proposal before
        if (
            ProposalsMapping[_proposalID].timeOfExecution != 0 &&
            ProposalsMapping[_proposalID].proposalDeadline < block.timestamp
        ) revert InvalidProposal(); //proposal must not been executed or expired
        if (BoardMemberVoted[_proposalID][msg.sender] == true)
            revert InvalidVoter(); //cant vote twice
        if (governanceNFT.ownerOf(tokenID) != msg.sender) revert InvalidVoter(); //msut have governance nft to vote
        if (governanceNFT.VotingPower(tokenID) < numOfVotes)
            revert InvalidVotingPower();
        if (ProposalsMapping[_proposalID].vetoed == true)
            revert InvalidProposal();

        //mark member as voted.
        BoardMemberVoted[_proposalID][msg.sender] == true;

        //vote
        VoteCount[_proposalID] += numOfVotes;

        emit Voted(msg.sender, numOfVotes, _proposalID);
    }

    // gated function
    function veto(bytes32 _proposalID) external onlyOwner returns (bool) {
        Proposal storage proposal = ProposalsMapping[_proposalID];
        proposal.vetoed = true;

        emit Vetoed(_proposalID);

        return true;
    }

    function execute(
        bytes32 _proposalID
    ) external payable returns (bool, uint timeOfExecution) {
        Proposal storage proposal = ProposalsMapping[_proposalID];

        //must pass the minimum votes threshold
        if (getProposalStatus(_proposalID) != ProposalStatus.passed)
            revert InvalidProposal();

        //execute
        proposal.timeOfExecution = uint40(block.timestamp);
        address target = proposal.proposalTarget;
        bytes memory proposalTxData = proposal.proposalTxData;
        (bool s, bytes memory r) = target.call{value: msg.value}(
            proposalTxData
        );
        require(s == true, "execution failed");

        emit Executed(_proposalID, block.timestamp);
        return (s, block.timestamp);
    }

    

    function getProposalStatus(
        bytes32 _proposalID
    ) public view returns (ProposalStatus status) {
        Proposal memory proposal = ProposalsMapping[_proposalID];

        if (proposal.vetoed) {
            return ProposalStatus.vetoed;
        }

        if (proposal.timeOfExecution > 0) {
            return ProposalStatus.executed;
        }

        if (block.timestamp > proposal.proposalDeadline) {
            return ProposalStatus.expired;
        }

        if (
            VoteCount[_proposalID] >=
            ((governanceNFT.totalVotingPower() * minVotesThreshhold) * 1e18) /
                (1e4 * 1e18)
        ) {
            return ProposalStatus.passed;
        }

        if (proposal.proposalDeadline > block.timestamp) {
            return ProposalStatus.active;
        }
    }

    receive() external payable {
        emit ReceivedEther(msg.value, msg.sender);
    }
}
