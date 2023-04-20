// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import {IAllowanceTransfer} from "./IAllowanceTransfer.sol";

interface IAllowanceTransferNFT is IAllowanceTransfer {
    struct PermitNFTDetails {
        // ERC721 & ERC1155 token address
        address token;
        // ERC721 & ERC1155 token id
        uint248 tokenId;
        // type id: 0 ERC721 1 ERC1155
        uint8 typeId;
        // the maximum amount allowed to spend
        uint160 amount;
        // timestamp at which a spender's token allowances become invalid
        uint48 expiration;
        // an incrementing value indexed per owner,token,and spender for each signature
        uint48 nonce;
    }

    struct PermitNFTSingle {
        // the permit data for a single token alownce
        PermitNFTDetails details;
        // address permissioned on the allowed tokens
        address spender;
        // deadline on the permit signature
        uint256 sigDeadline;
    }

    struct TokenNFTSpenderPair {
        // the token the spender is approved
        address token;
        // ERC721 & ERC1155 token id
        uint248 tokenId;
        // the spender address
        address spender;
    }

    event ApprovalNFT(address indexed owner, address indexed token, address indexed spender, uint248 tokenId, uint160 amount, uint48 expiration);
    event PermitNFT(address indexed owner, address indexed token, address indexed spender, uint248 tokenId, uint160 amount, uint48 expiration, uint48 nonce);
    event NonceInvalidationNFT(address indexed owner, address indexed token, address indexed spender, uint248 tokenId, uint48 newNonce, uint48 oldNonce);
    event LockdownNFT(address indexed owner, address indexed token, address indexed spender, uint248 tokenId);

    function allowanceNFT(address, address, uint256, address) external view returns (uint160, uint48, uint48);
    function approveNFT(address token, uint256 tokenId, address spender, uint160 amount, uint48 expiration) external;
    function permitNFT(address owner, PermitNFTSingle memory permitSingle, bytes calldata signature) external;
    function transferNFTFrom(address from, address to, uint248 tokenId, uint8 typeId, uint160 amount, address token) external;
    // function transferNFTFrom(AllowanceTransferDetails[] calldata transferDetails) external;
    function lockdownNFT(TokenNFTSpenderPair[] calldata approvals) external;
    function invalidateNFTNonces(address token, uint256 tokenId, address spender, uint48 newNonce) external;
}
