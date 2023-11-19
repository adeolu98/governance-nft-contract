// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GovernanceNFT is ERC721, ERC721Burnable, Ownable {
    uint256 private _nextTokenId;
    mapping(uint => uint) public VotingPower;
    uint public totalVotingPower;
    uint public minVotingPower;
    uint public maxVotingPower;
    uint public maxTotalVotingPower;

    error InvalidVotingPower();

    constructor(
        address initialOwner,
        uint _minVotingPower,
        uint _maxVotingPower,
        uint _maxTotalVotingPower
    ) ERC721("MyToken", "MTK") Ownable(initialOwner) {
        require(_maxVotingPower < _maxTotalVotingPower, "invalid maxVotingPower");
        require( _minVotingPower < _maxVotingPower, "invalid _minVotingPower");
        minVotingPower = _minVotingPower;
        maxVotingPower = _maxVotingPower;
        maxTotalVotingPower = _maxTotalVotingPower;
    }

    function mint(address to, uint _votingPower) public onlyOwner {
        if (_votingPower < minVotingPower || _votingPower > maxVotingPower)
            revert InvalidVotingPower();
        if (_votingPower + totalVotingPower > maxTotalVotingPower) {
            _votingPower = maxTotalVotingPower - totalVotingPower;
        }
        if (_votingPower == 0) revert InvalidVotingPower();

        uint256 tokenId = _nextTokenId++;
        VotingPower[tokenId] = _votingPower;
        totalVotingPower += _votingPower;

        _safeMint(to, tokenId);
    }

    function burn( uint _tokenId ) public override onlyOwner {
        uint _votingPower = VotingPower[_tokenId];
        VotingPower[_tokenId] = 0;
        totalVotingPower -= _votingPower;
        _burn(_tokenId);
    }
}
