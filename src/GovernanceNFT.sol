// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title NFT used to validate membership of the GoverningBoard
/// @author github:adeolu98
/// @notice mints membership nfts to new members, burns nfts of leaving board members
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
        require(
            _maxVotingPower < _maxTotalVotingPower,
            "invalid maxVotingPower"
        );
        require(_minVotingPower < _maxVotingPower, "invalid _minVotingPower");
        minVotingPower = _minVotingPower;
        maxVotingPower = _maxVotingPower;
        maxTotalVotingPower = _maxTotalVotingPower;
    }

    /// @notice mints nft to member, assigns a voting power to the nft, only owner can mint
    /// @dev during mint, validtes the votingPower amount, assigns voting power to nft tokenID, increases total voting power.
    /// @param Documents a parameter just like in doxygen (must be followed by parameter name)
    /// @return Documents the return variables of a contract’s function state variable
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

    /// @notice burns nft from a leaving member, callable by owner only
    /// @dev bruns nft, deletes nft voting power, reduces totalVotingPower
    /// @param _tokenId id of token to be burned
    function burn(uint _tokenId) public override onlyOwner {
        uint _votingPower = VotingPower[_tokenId];
        VotingPower[_tokenId] = 0;
        totalVotingPower -= _votingPower;
        _burn(_tokenId);
    }
}
