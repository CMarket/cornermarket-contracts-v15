//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../permit2/interfaces/IAllowanceTransferNFT.sol";
import "../permit2/libraries/SafeCast160.sol";
import "./library/TransferHelper.sol";

contract AgentNFT is AccessControl, ERC721Enumerable {
    using Counters for Counters.Counter;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IAllowanceTransferNFT internal immutable permit2;
    string public baseURI;
    address public immutable payToken;
    Counters.Counter private _tokenId;

    event Withdraw(address account, address token, uint withdrawAmount);
    event BaseURIChange(string newURI, string oldURI);

    constructor(string memory _uri, address _payToken, address _permit2) ERC721("CornerMarket Agent Badge", "CMAB") {
        permit2 = IAllowanceTransferNFT(_permit2);
        payToken = _payToken;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
        baseURI = _uri;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function setBaseURI(string calldata _baseURI)  external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit BaseURIChange(_baseURI, baseURI);
        baseURI = _baseURI;
    }

    function tokenURI(uint tokenId) public view virtual override returns (string memory) {
        return string(abi.encodePacked(baseURI, Strings.toString(tokenId)));
    }

    function currentTokenId() public view returns (uint) {
        return _tokenId.current();
    }

    function _mintTo(address receiver) internal onlyRole(OPERATOR_ROLE) returns (uint)  {
        _tokenId.increment();
        uint tokenId = _tokenId.current();
        _mint(receiver, tokenId);
        return tokenId;
    }

    function mintBehalf(address user, uint nftPrice, IAllowanceTransferNFT.PermitSingle calldata _permit, bytes calldata _signature) external onlyRole(OPERATOR_ROLE) {
        if (nftPrice > 0) {
            require(_permit.details.token == payToken, "unmatched token");
            permit2.permit(user, _permit, _signature);
            permit2.transferFrom(user, address(this), SafeCast160.toUint160(nftPrice), _permit.details.token);
        }
        _mintTo(user);
    }

    function withdraw(address token, uint amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) {
            TransferHelper.safeTransferETH(msg.sender, amount);
        } else {
            TransferHelper.safeTransfer(token, msg.sender, amount);
        }
        emit Withdraw(msg.sender, token, amount);
    }
}
