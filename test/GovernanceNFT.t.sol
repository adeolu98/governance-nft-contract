// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {GovernanceNFT} from "../src/GovernanceNFT.sol";
import {GoverningBoard} from "../src/GoverningBoard.sol";
import {SetUpContractsTest} from "./SetUpContracts.t.sol";

contract GovernanceNftTest is Test, SetUpContractsTest {
    function setUp() public override {
        super.setUp();
    }

    function testMint() public {
        uint votingPowerAmt = 10;
        vm.prank(owner);
        uint tokenID = governanceNFT.mint(address(10), votingPowerAmt);

        assertEq(governanceNFT.ownerOf(tokenID), address(10));
        assertEq(governanceNFT.VotingPower(tokenID), votingPowerAmt);
        assertEq(governanceNFT.totalVotingPower(), votingPowerAmt);
    }

    function testMintWithVotingPowerOutsideMinMaxRange() public {
        uint votingPowerAmtBelowMin = 1;
        uint votingPowerAmtAboveMax = 100;

        vm.startPrank(owner);
        //deploy new governance
        uint _minVotingPower = 10;
        uint _maxVotingPower = 20;
        uint _maxTotalVotingPower = 100;
        GovernanceNFT newGovernanceNFT = new GovernanceNFT(
            _minVotingPower,
            _maxVotingPower,
            _maxTotalVotingPower
        );

        vm.expectRevert(GovernanceNFT.InvalidVotingPower.selector);
        newGovernanceNFT.mint(address(10), votingPowerAmtBelowMin);

        vm.expectRevert(GovernanceNFT.InvalidVotingPower.selector);
        newGovernanceNFT.mint(address(10), votingPowerAmtAboveMax);
        vm.stopPrank();
    }

    function testMintWithVotingPowerThatTakesTotalAboveMaxTotal() public {
        uint votingPowerAmt = governanceNFT.maxVotingPower();

        vm.startPrank(owner);
        //mint to 4 addresses the max amount allowed per member

        for (uint256 index = 1; index < 5; index++) {
            uint tokenID = governanceNFT.mint(
                address(uint160(index)),
                votingPowerAmt
            );
            assertEq(governanceNFT.ownerOf(tokenID), address(uint160(index)));
            assertEq(governanceNFT.VotingPower(tokenID), votingPowerAmt);
        }

        //mint to 5th address half of remaining voting power available
        uint votingPowerOfAddr5 = (governanceNFT.maxTotalVotingPower() -
            governanceNFT.totalVotingPower()) / 2;
        governanceNFT.mint(address(uint160(5)), votingPowerOfAddr5);

        //at this point totalVotingPower is 90, 20+20+20+20+10 = 90

        //mint to 6th address voting power amount that takes totalVotingPower above maxTotalVotingPower
        uint votingPowerOfAddr6 = governanceNFT.maxTotalVotingPower() -
            governanceNFT.totalVotingPower(); //10
        uint tokenIDMintedToAddr6 = governanceNFT.mint(
            address(uint160(6)),
            votingPowerOfAddr6 + 5 //15, this will increase totalVotingPower to 105, maxTotalVotingPower is 100
        );
        // assert that the max is obeyed and deductions are done to bring down the votingPower
        assertEq(governanceNFT.VotingPower(tokenIDMintedToAddr6), 10);
        assertEq(governanceNFT.totalVotingPower(), 100);

        // at the max amount for totalVotingPower i.e totalVotingPower == maxTotalVotingPower, try to mint more voting Power
        vm.expectRevert(GovernanceNFT.InvalidVotingPower.selector);
        governanceNFT.mint(address(uint160(7)), 20);

        vm.stopPrank();
    }

    function testMintToSameAddressTwice() public {
        vm.startPrank(owner);
        governanceNFT.mint(address(1), 20);

        vm.expectRevert(GovernanceNFT.CannotOwnMoreThanOne.selector);
        governanceNFT.mint(address(1), 20);
    }

    function testBurn() public {
        vm.startPrank(owner);
        uint tokenId = governanceNFT.mint(address(1), 20);

        // now burn the token minted to address(1)
        governanceNFT.burn(tokenId);

        vm.expectRevert();
        governanceNFT.ownerOf(tokenId); // will revert since token is inexistent

        //assert voting power for token is deleted
        assertEq(governanceNFT.VotingPower(tokenId), 0);
        vm.stopPrank();
    }

    function testBurnAndMintToSameAddr() public {
        testBurn();
        //since we have burned from address(1), let us mint back to address 1
        vm.startPrank(owner);
        uint tokenId = governanceNFT.mint(address(1), 20);
        assertEq(governanceNFT.ownerOf(tokenId), address(1));
        vm.stopPrank();
    }

    function testMintOnlyOwner() public {
        uint votingPowerAmt = 10;
        vm.expectRevert(); //since we dont call with owner address
        vm.prank(address(300));
        governanceNFT.mint(address(10), votingPowerAmt);
    }

    function testBurnOnlyOwner() public {
        vm.prank(owner);
        uint tokenId = governanceNFT.mint(address(1), 20);

        // now try to burn the token minted to address(1) when caller is not owner
        vm.expectRevert();
        vm.prank(address(300));
        governanceNFT.burn(tokenId);
    }
}
