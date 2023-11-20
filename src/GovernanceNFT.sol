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
    uint256 public totalVotingPower;
    uint256 public minVotingPower;
    uint256 public maxVotingPower;
    uint256 public maxTotalVotingPower;

    mapping(uint256 => uint256) public VotingPower;
    mapping(address => bool) private mintedTo;

    error InvalidVotingPower();
    error CannotOwnMoreThanOne();

    constructor(
        uint256 _minVotingPower,
        uint256 _maxVotingPower,
        uint256 _maxTotalVotingPower
    ) ERC721("MyToken", "MTK") Ownable(msg.sender) {
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
    /// @param _to is address nft should be minted to
    /// @param _votingPower is amount of voting power to assign to the new nft
    function mint(
        address _to,
        uint256 _votingPower
    ) public onlyOwner returns (uint256 tokenId) {
        if (_votingPower < minVotingPower || _votingPower > maxVotingPower)
            revert InvalidVotingPower();
        if (_votingPower + totalVotingPower > maxTotalVotingPower) {
            _votingPower = maxTotalVotingPower - totalVotingPower;
        }
        if (_votingPower == 0) revert InvalidVotingPower();
        if (mintedTo[_to] == true) revert CannotOwnMoreThanOne();

        tokenId = _nextTokenId++;
        VotingPower[tokenId] = _votingPower;
        totalVotingPower += _votingPower;
        mintedTo[_to] = true;

        _safeMint(_to, tokenId);
    }

    /// @notice burns nft from a leaving member, callable by owner only
    /// @dev bruns nft, deletes nft voting power, reduces totalVotingPower
    /// @param _tokenId id of token to be burned
    function burn(uint256 _tokenId) public override onlyOwner {
        address member = ownerOf(_tokenId);
        uint256 _votingPower = VotingPower[_tokenId];
        delete VotingPower[_tokenId];
        totalVotingPower -= _votingPower;
        mintedTo[member] = false; // this will allow the member address to take another token id if address wants to become a member again
        _burn(_tokenId);
    }
}
