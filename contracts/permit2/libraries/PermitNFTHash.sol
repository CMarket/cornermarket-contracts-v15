// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IAllowanceTransferNFT} from "../interfaces/IAllowanceTransferNFT.sol";
import {ISignatureTransfer} from "../interfaces/ISignatureTransfer.sol";

library PermitNFTHash {
    bytes32 public constant _PERMIT_DETAILS_TYPEHASH =
        keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");
    bytes32 public constant _PERMIT_NFT_DETAILS_TYPEHASH =
        keccak256("PermitNFTDetails(address token,uint248 tokenId,uint8 typeId,uint160 amount,uint48 expiration,uint48 nonce)");

    bytes32 public constant _PERMIT_SINGLE_NFT_TYPEHASH = keccak256(
        "PermitNFTSingle(PermitNFTDetails details,address spender,uint256 sigDeadline)PermitNFTDetails(address token,uint248 tokenId,uint8 typeId,uint160 amount,uint48 expiration,uint48 nonce)"
    );
    bytes32 public constant _PERMIT_SINGLE_BUY_NFT_TYPEHASH = keccak256(
        "PermitNFTSingle(PermitDetails details,uint256 tokenId,uint8 typeId,uint256 nftAmount,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
    );

    function hash(IAllowanceTransferNFT.PermitNFTSingle memory permitSingle) internal pure returns (bytes32) {
        bytes32 permitHash = _hashPermitDetails(permitSingle.details);
        return
            keccak256(abi.encode(_PERMIT_SINGLE_NFT_TYPEHASH, permitHash, permitSingle.spender, permitSingle.sigDeadline));
    }

    function _hashPermitDetails(IAllowanceTransferNFT.PermitNFTDetails memory details) private pure returns (bytes32) {
        return keccak256(abi.encode(_PERMIT_NFT_DETAILS_TYPEHASH, details));
    }

    function hash(IAllowanceTransferNFT.PermitBuyNFTSingle memory permitSingle) internal pure returns (bytes32) {
        bytes32 permitHash = _hashPermitDetails(permitSingle.details);
        return
            keccak256(abi.encode(_PERMIT_SINGLE_BUY_NFT_TYPEHASH, permitHash, permitSingle.tokenId, permitSingle.typeId, permitSingle.nftAmount, permitSingle.spender, permitSingle.sigDeadline));
    }

    function _hashPermitDetails(IAllowanceTransferNFT.PermitDetails memory details) private pure returns (bytes32) {
        return keccak256(abi.encode(_PERMIT_DETAILS_TYPEHASH, details));
    }
}
