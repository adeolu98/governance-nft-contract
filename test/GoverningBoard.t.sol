// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {GovernanceNFT} from "../src/GovernanceNFT.sol";
import {GoverningBoard} from "../src/GoverningBoard.sol";
import {SetUpContractsTest} from "./SetUpContracts.t.sol";

contract GoverningBoardTest is Test, SetUpContractsTest {
    //demoProposal
    GoverningBoard.Proposal demoProposal =
        GoverningBoard.Proposal({
            proposer: address(0),
            proposalTarget: address(0),
            proposalTxData: "",
            proposalDeadline: uint40(block.timestamp + 30 days), // check that proposal deadline must be >= now when making proposals.
            timeOfExecution: 0,
            vetoed: false
        });

    struct BoardMember {
        address memberAddress;
        uint tokenID;
    }

    BoardMember memberTwo = BoardMember(makeAddr("memberTwo"), 0);
    BoardMember memberThree = BoardMember(makeAddr("memberThree"), 0);
    BoardMember memberFour = BoardMember(makeAddr("memberFour"), 0);
    address proposerAddr = makeAddr("proposer");

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        memberTwo.tokenID = governanceNFT.mint(
            memberTwo.memberAddress,
            governanceNFT.maxVotingPower()
        );
        memberThree.tokenID = governanceNFT.mint(
            memberThree.memberAddress,
            governanceNFT.maxVotingPower()
        );
        memberFour.tokenID = governanceNFT.mint(
            memberFour.memberAddress,
            governanceNFT.maxVotingPower()
        );
        vm.stopPrank();
    }

    function testPropose()
        public
        returns (uint proposerTokenID, bytes32 proposalID)
    {
        GoverningBoard.Proposal memory _proposal = demoProposal;

        //mint to proposer
        vm.prank(owner);
        proposerTokenID = governanceNFT.mint(proposerAddr, 20);

        vm.prank(proposerAddr);
        _proposal.proposer = proposerAddr;
        proposalID = governingBoard.propose(_proposal, uint40(proposerTokenID));
    }

    function testProposeWithInvalidDeadline() public {
        GoverningBoard.Proposal memory _proposal = demoProposal;
        _proposal.proposalDeadline = uint40(100);
        //mint to proposer
        vm.prank(owner);
        uint proposerTokenID = governanceNFT.mint(proposerAddr, 20);

        vm.warp(10000000);
        vm.prank(proposerAddr);
        vm.expectRevert(GoverningBoard.InvalidDeadline.selector);
        _proposal.proposer = proposerAddr;
        governingBoard.propose(_proposal, uint40(proposerTokenID));
    }

    function testProposeWithInvalidCaller() public {
        GoverningBoard.Proposal memory _proposal = demoProposal;
        _proposal.proposalDeadline = uint40(100);
        //mint to proposer
        vm.prank(owner);
        uint proposerTokenID = governanceNFT.mint(proposerAddr, 20);

        vm.prank(proposerAddr);
        vm.expectRevert(GoverningBoard.InvalidCaller.selector);
        //change proposer to another address
        _proposal.proposer = address(1);
        governingBoard.propose(_proposal, uint40(proposerTokenID));
    }

    function testProposeWithAlreadyProposedProposal() public {
        (uint proposerTokenID, bytes32 originalProposalID) = testPropose();
        GoverningBoard.Proposal memory _proposal = demoProposal;

        //try to propose the exact same proposal again..
        vm.expectRevert(GoverningBoard.AlreadyProposed.selector);
        vm.prank(proposerAddr);
        _proposal.proposer = proposerAddr;
        bytes32 copyProposalID = governingBoard.propose(
            _proposal,
            uint40(proposerTokenID)
        );
    }

    function testProposeAlreadyExecutedProposal() public {
        (uint proposerTokenID, bytes32 originalProposalID) = testPropose();

        //vote with members
        vm.prank(memberTwo.memberAddress);
        governingBoard.vote(originalProposalID, memberTwo.tokenID, 20);
        vm.prank(memberThree.memberAddress);
        governingBoard.vote(originalProposalID, memberThree.tokenID, 20);

        //at the point we have enough votes (60 out of 100) for execution.
        governingBoard.execute(originalProposalID);

        //try to propose executed proposal again
        vm.expectRevert(GoverningBoard.AlreadyProposed.selector);
        vm.prank(proposerAddr);
        GoverningBoard.Proposal memory _proposal = demoProposal;
        _proposal.proposer = proposerAddr;
        governingBoard.propose(_proposal, uint40(proposerTokenID));
    }

    function testProposeActionAddProposalVoteToProposal() public {
        (uint proposerTokenID, bytes32 proposalID) = testPropose();
        //check that the initial votes with proposal is all the votes of the proposer
        assertEq(
            governanceNFT.VotingPower(proposerTokenID),
            governingBoard.VoteCount(proposalID)
        );
    }

    function testVoteOnProposal() public {
        (uint proposerTokenID, bytes32 proposalID) = testPropose();
        uint voteCountBeforeMemberVote = governingBoard.VoteCount(proposalID);

        //vote
        vm.prank(memberTwo.memberAddress);
        governingBoard.vote(proposalID, memberTwo.tokenID, 10);

        uint voteCountAfterMemberVote = governingBoard.VoteCount(proposalID);

        assertGt(voteCountAfterMemberVote, voteCountBeforeMemberVote);
    }

    function testCantVoteOnExecutedProposal() public {
        //it must not be already eecuted, vetoed or expired

        //EXECUTED PROPOSALS
        (uint proposerTokenID, bytes32 proposalID) = testPropose();
        //vote to make the proposal executable
        _vote(
            proposalID,
            memberTwo.tokenID,
            governanceNFT.VotingPower(memberTwo.tokenID)
        );
        _vote(
            proposalID,
            memberThree.tokenID,
            governanceNFT.VotingPower(memberThree.tokenID)
        );
        //execute it
        require(_execute(proposalID) == true);

        //now try to vote again
        vm.expectRevert(GoverningBoard.InvalidProposal.selector);
        governingBoard.vote(proposalID, memberFour.tokenID, 10);
    }

    function testCantVoteOnVetoedProposal() public {
        //it must not be  vetoed

        (uint proposerTokenID, bytes32 proposalID) = testPropose();

        //veto it
        vm.prank(owner);
        governingBoard.veto(proposalID);

        //now try to vote again
        vm.expectRevert(GoverningBoard.InvalidProposal.selector);
        governingBoard.vote(proposalID, memberFour.tokenID, 10);
    }

    function testCantVoteOnExpiredProposal() public {
        //it must not be  expired.

        (uint proposerTokenID, bytes32 proposalID) = testPropose();

        vm.warp(block.timestamp + 365 days); //this is way past the proposal deadline

        //now try to vote again
        vm.expectRevert(GoverningBoard.InvalidProposal.selector);
        governingBoard.vote(proposalID, memberFour.tokenID, 10);
    }

    function testCantVoteTwice() public {
        (uint proposerTokenID, bytes32 proposalID) = testPropose();
        uint numOfVotes = governanceNFT.VotingPower(memberTwo.tokenID) / 2;
        //try to vote twice
        vm.startPrank(memberTwo.memberAddress);
        governingBoard.vote(proposalID, memberTwo.tokenID, numOfVotes);

        vm.expectRevert(GoverningBoard.InvalidVoter.selector);
        governingBoard.vote(proposalID, memberTwo.tokenID, numOfVotes);
        vm.stopPrank();
    }

    function testMustBeNftHolderToVote() public {
        (uint proposerTokenID, bytes32 proposalID) = testPropose();

        //now try to vote again
        vm.expectRevert(GoverningBoard.InvalidVoter.selector);
        vm.prank(address(200)); //random address tries to call with a valid member token id
        governingBoard.vote(proposalID, memberFour.tokenID, 10);
    }

    function testCantVoteWithMoreThanVotingPower() public {
        (uint proposerTokenID, bytes32 proposalID) = testPropose();

        //now try to vote with more than voting power
        vm.expectRevert(GoverningBoard.InvalidVotingPower.selector);
        vm.prank(memberThree.memberAddress); //random address tries to call with a valid member token id
        governingBoard.vote(proposalID, memberThree.tokenID, 1e18);
    }

    function testCantVoteWithZeroAmount() public {
        (uint proposerTokenID, bytes32 proposalID) = testPropose();

        //now try to vote with more zero amount
        vm.expectRevert(GoverningBoard.InvalidVotingPower.selector);
        vm.prank(memberThree.memberAddress); //random address tries to call with a valid member token id
        governingBoard.vote(proposalID, memberThree.tokenID, 0);
    }

    function testVeto() public {
        (uint proposerTokenID, bytes32 proposalID) = testPropose();

        vm.prank(owner);
        governingBoard.veto(proposalID);

        assert(
            governingBoard.getProposalStatus(proposalID) ==
                GoverningBoard.ProposalStatus.vetoed
        );
    }

    function testVetoOnlyOwner() public {
        (uint proposerTokenID, bytes32 proposalID) = testPropose();

        vm.expectRevert();
        governingBoard.veto(proposalID);

        assert(
            governingBoard.getProposalStatus(proposalID) ==
                GoverningBoard.ProposalStatus.active
        );
    }

    function testExecute() public returns (uint, bytes32) {
        (uint proposerTokenID, bytes32 proposalID) = testPropose();
        //vote to make the proposal executable
        _vote(
            proposalID,
            memberTwo.tokenID,
            governanceNFT.VotingPower(memberTwo.tokenID)
        );
        _vote(
            proposalID,
            memberThree.tokenID,
            governanceNFT.VotingPower(memberThree.tokenID)
        );

        //status must be passed
        assert(
            governingBoard.getProposalStatus(proposalID) ==
                GoverningBoard.ProposalStatus.passed
        );

        require(_execute(proposalID) == true);
        return (proposerTokenID, proposalID);
    }

    function testChangeMinThreshold() public {
        uint valueInRange = 1e3; //value is between 1e2 to 1e4
        uint valueBelow1e2 = 0;
        uint valueAbove1e4 = 1e18;
        vm.startPrank(owner);
        governingBoard.changeMinThreshold(valueInRange);

        vm.expectRevert("invalid votes threshold");
        governingBoard.changeMinThreshold(valueBelow1e2);

        vm.expectRevert("invalid votes threshold");
        governingBoard.changeMinThreshold(valueAbove1e4);

        vm.stopPrank();

        vm.expectRevert(); //expect revert when caller is not owner
        governingBoard.changeMinThreshold(valueAbove1e4);
    }

    function testWithdraw() public {
        vm.deal(address(governingBoard), 1 ether);

        vm.prank(owner);
        governingBoard.withdrawEth();
        assertEq(owner.balance, 1 ether);

        //test that only owner can call
        vm.expectRevert();
        governingBoard.withdrawEth();
    }

    function _execute(bytes32 _proposalID) internal returns (bool) {
        (bool s, ) = governingBoard.execute(_proposalID);
        return s;
    }

    function _vote(
        bytes32 _proposalID,
        uint _tokenID,
        uint _numOfVotes
    ) internal {
        vm.prank(governanceNFT.ownerOf(_tokenID));
        governingBoard.vote(_proposalID, _tokenID, _numOfVotes);
    }

    function _veto(bytes32 _proposalID) internal returns (bool) {
        vm.prank(owner);
        return governingBoard.veto(_proposalID);
    }
}
