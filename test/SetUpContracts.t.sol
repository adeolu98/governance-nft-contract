// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {GovernanceNFT} from "../src/GovernanceNFT.sol";
import {GoverningBoard} from "../src/GoverningBoard.sol";

contract SetUpContractsTest is Test {
    GovernanceNFT public governanceNFT;
    GoverningBoard public governingBoard;

    address public owner = makeAddr("owner");

    function setUp() public virtual {
        uint _minVotingPower = 1;
        uint _maxVotingPower = 20;
        uint _maxTotalVotingPower = 100;
        uint _minVotesThreshhold = 5000; //50%

        vm.startPrank(owner);
        governanceNFT = new GovernanceNFT(
            _minVotingPower,
            _maxVotingPower,
            _maxTotalVotingPower
        );
        governingBoard = new GoverningBoard(governanceNFT, _minVotesThreshhold);
        vm.stopPrank();
    }
}
