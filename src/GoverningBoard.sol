// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./GovernanceNFT.sol";

/// @title GoverningBoard, a contract that implements governance processes
/// @author github:adeolu98
/** 
 @dev  GoverningBoard should: 
- allow BoardMembers to vote, create and execute proposals 
- allow contract owner to veto a proposal
*/

contract GoverningBoard is Ownable {
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

    GovernanceNFT private governanceNFT;
    uint public minVotesThreshhold; //where 1e4 means 100%, 1% = 1e2

    mapping(bytes32 => Proposal) public ProposalsMapping;
    mapping(bytes32 => uint) public VoteCount;
    mapping(bytes32 => mapping(address => bool)) public BoardMemberVoted;

    event Proposed(bytes32 proposalID, uint currentTimeStamp);
    event Voted(address voter, uint votes, bytes32 proposalID);
    event Executed(bytes32 proposalID, uint time);
    event Vetoed(bytes32 proposalID);
    event ReceivedEther(uint value, address sender);
    event ChangedMinVotesThreshhold(uint newMinVotesThreshhold);
    event WithdrawnETH(uint amountToWithdraw);

    error InvalidDeadline();
    error InvalidTimeOfExecution();
    error InvalidProposal();
    error InvalidVoter();
    error InvalidVotingPower();
    error NotEnoughVotes();
    error AlreadyProposed();
    error InvalidCaller();

    //@param _governanceNFT is the address of the NFT token
    //@param _minVotesThreshhold is the minimum threshold for votes on a proposal,
    //represented as 1e4 = 100% or 1% = 1e2 just like percentages. Each proposal must have votes
    //summed up to be >= the mimumthreshold. e.g if threshold is 20%, and there are 10 totalVotes,
    //the proposal must have 2 or more votes.
    //@dev checks the _minVotesThreshhold to be in range and sets the values in storage
    constructor(
        GovernanceNFT _governanceNFT,
        uint _minVotesThreshhold
    ) Ownable(msg.sender) {
        require(
            _minVotesThreshhold >= 1e2 && _minVotesThreshhold <= 1e4,
            "invalid votes threshold"
        );
        require(address(_governanceNFT) != address(0), "cant set to addr(0)");
        governanceNFT = _governanceNFT;
        minVotesThreshhold = _minVotesThreshhold;
    }

    /// @notice this function is used to make proposals for the governance process.
    /// only the nft token holders can propose.
    /// @param _proposal contains a Proposal struct of the proposal properties
    /// @param _tokenID is the token id of the nft holder.
    /// @dev checks validity of inputs and adds proposal to proposal mapping, proposer votes on its proposal with all his votes.
    /// @return returns the new proposal ID
    function propose(
        Proposal memory _proposal,
        uint40 _tokenID
    ) external returns (bytes32) {
        if (_proposal.proposalDeadline < block.timestamp)
            revert InvalidDeadline();
        if (_proposal.timeOfExecution != 0) revert InvalidTimeOfExecution();
        if (_proposal.proposer != msg.sender) revert InvalidCaller();

        // add new proposal to proposals mapping
        bytes32 proposalID = keccak256(
            abi.encode(
                _proposal.proposalTarget,
                _proposal.proposalDeadline,
                _proposal.proposalTxData,
                _proposal.proposer
            )
        );

        //cant propose already proposed proposal
        //should not propose/execute same proposal twice, something must be different, deadline for example.
        if (ProposalsMapping[proposalID].proposalDeadline > 0)
            revert AlreadyProposed();

        //add proposal to mapping
        ProposalsMapping[proposalID] = _proposal;

        //the proposer must vote on his proposal. to vote you must be an nft holder.
        vote(proposalID, _tokenID, governanceNFT.VotingPower(_tokenID));

        emit Proposed(proposalID, block.timestamp);
        return proposalID;
    }

    /// @notice allows members of then board to vote on proposals, user can decide to put all of their votes behind a proposal to fully support it
    /// or put the least amount to show the least bit of support.
    /// @dev function does input validation, then adds the new vote and marks member as voted. member cant vote twice.
    /// @param _proposalID the ID of the proposal to vote on
    /// @param _tokenID the nft tokenID owned by the caller
    /// @param _numOfVotes the amount of a members total votes the member wants to use to back the proposal,
    /// all for full support, least amount for least amount of support
    function vote(bytes32 _proposalID, uint _tokenID, uint _numOfVotes) public {
        //check that proposal is not vetoed, expired or executed and check that user has not voted on the proposal before
        if (
            getProposalStatus(_proposalID) != ProposalStatus.passed &&
            getProposalStatus(_proposalID) != ProposalStatus.active
        ) revert InvalidProposal(); //proposal must not been executed or expired
        if (BoardMemberVoted[_proposalID][msg.sender] == true)
            revert InvalidVoter(); //cant vote twice
        if (governanceNFT.ownerOf(_tokenID) != msg.sender)
            revert InvalidVoter(); //msut have governance nft to vote
        if (governanceNFT.VotingPower(_tokenID) < _numOfVotes)
            revert InvalidVotingPower();
        if (_numOfVotes == 0) revert InvalidVotingPower();

        //mark member as voted.
        BoardMemberVoted[_proposalID][msg.sender] = true;

        //vote
        VoteCount[_proposalID] += _numOfVotes;

        emit Voted(msg.sender, _numOfVotes, _proposalID);
    }

    /// @notice callable by owner only. in some rare cases owner may step in to cancel faulty proposals
    /// @dev sets proposal's vetoed status to be true.
    /// @param _proposalID the ID of the proposal to veto
    /// @return true after success
    function veto(bytes32 _proposalID) external onlyOwner returns (bool) {
        Proposal storage proposal = ProposalsMapping[_proposalID];
        proposal.vetoed = true;

        emit Vetoed(_proposalID);

        return true;
    }

    /// @notice executes a passed proposal.
    /// @dev proposal status must be passed, timeOfExecution is set in storage and execution is done
    /// @param _proposalID the ID of the proposal to execute
    /// @return true if sucessfull and return the timeOfExecution.
    function execute(
        bytes32 _proposalID
    ) external payable returns (bool, uint timeOfExecution) {
        Proposal storage proposal = ProposalsMapping[_proposalID];

        //must pass the minimum votes threshold
        if (getProposalStatus(_proposalID) != ProposalStatus.passed)
            revert InvalidProposal();

        //execute
        proposal.timeOfExecution = uint40(block.timestamp); //this is set before execution to prevent reentry
        address target = proposal.proposalTarget;
        bytes memory proposalTxData = proposal.proposalTxData;
        (bool s, ) = target.call{value: msg.value}(proposalTxData);
        require(s == true, "execution failed");

        emit Executed(_proposalID, block.timestamp);
        return (s, block.timestamp);
    }

    /// @notice returns the status of the proposal
    /// @param _proposalID the ID of the proposal to check
    /// @return status is the status of proposal, it is of type enum ProposalStatus.
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

    /// @notice changes the value of minVotesThreshhold
    /// @param _minVotesThreshhold is the new minVotesThreshhold value to be set
    function changeMinThreshold(uint _minVotesThreshhold) external onlyOwner {
        require(
            _minVotesThreshhold >= 1e2 && _minVotesThreshhold <= 1e4,
            "invalid votes threshold"
        );
        minVotesThreshhold = _minVotesThreshhold;
        emit ChangedMinVotesThreshhold(_minVotesThreshhold);
    }

    /// @notice withdraw excess eth, callable by owner
    function withdrawEth() public onlyOwner {
        uint amountToWithdraw = address(this).balance;
        payable(msg.sender).transfer(amountToWithdraw);

        emit WithdrawnETH(amountToWithdraw);
    }

    receive() external payable {
        emit ReceivedEther(msg.value, msg.sender);
    }
}
