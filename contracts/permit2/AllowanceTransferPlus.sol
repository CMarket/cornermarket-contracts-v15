// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {PermitNFTHash} from "./libraries/PermitNFTHash.sol";
import {SignatureVerification} from "./libraries/SignatureVerification.sol";
import {Allowance} from "./libraries/Allowance.sol";
import {IAllowanceTransferNFT} from "./interfaces/IAllowanceTransferNFT.sol";
import {AllowanceTransfer} from "./AllowanceTransfer.sol";
import {SignatureExpired, InvalidNonce} from "./PermitErrors.sol";

contract AllowanceTransferPlus is AllowanceTransfer, IAllowanceTransferNFT {
    using SignatureVerification for bytes;
    using PermitNFTHash for PermitNFTSingle;
    using Allowance for PackedAllowance;

    // mapping(address => mapping(address => mapping(address => PackedAllowance))) public allowance;
    mapping(address => mapping(address => mapping(uint => mapping(address => PackedAllowance)))) public allowanceNFT;

    /// @inheritdoc IAllowanceTransferNFT
    function approveNFT(address token, uint tokenId, address spender, uint160 amount, uint48 expiration) external {
        PackedAllowance storage allowed = allowanceNFT[msg.sender][token][tokenId][spender];
        allowed.updateAmountAndExpiration(amount, expiration);
        emit ApprovalNFT(msg.sender, token, spender, uint248(tokenId), amount, expiration);
    }

    /// @inheritdoc IAllowanceTransferNFT
    function permitNFT(address owner, PermitNFTSingle memory permitSingle, bytes calldata signature) external {
        if (block.timestamp > permitSingle.sigDeadline) revert SignatureExpired(permitSingle.sigDeadline);

        // Verify the signer address from the signature.
        signature.verify(_hashTypedData(permitSingle.hash()), owner);

        _updateNFTApproval(permitSingle.details, owner, permitSingle.spender);
    }

    /// @inheritdoc IAllowanceTransferNFT
    function transferNFTFrom(address from, address to, uint248 tokenId, uint8 typeId, uint160 amount, address token) external {
        _transferNFT(from, to, tokenId, typeId, amount, token);
    }

    function _transferNFT(address from, address to, uint248 tokenId, uint8 typeId, uint160 amount, address token) private {
        PackedAllowance storage allowed = allowanceNFT[from][token][tokenId][msg.sender];

        if (block.timestamp > allowed.expiration) revert AllowanceExpired(allowed.expiration);

        uint256 maxAmount = allowed.amount;
        if (maxAmount != type(uint160).max) {
            if (amount > maxAmount) {
                revert InsufficientAllowance(maxAmount);
            } else {
                unchecked {
                    allowed.amount = uint160(maxAmount) - amount;
                }
            }
        }

        // Transfer the tokens from the from address to the recipient.
        if (typeId == 1) {
            IERC721(token).safeTransferFrom(from, to, tokenId, "");
        } else if (typeId == 2) {
            IERC1155(token).safeTransferFrom(from, to, tokenId, amount, "");
        }
    }

    function lockdownNFT(TokenNFTSpenderPair[] calldata approvals) external {
        address owner = msg.sender;
        // Revoke allowances for each pair of spenders and tokens.
        unchecked {
            uint256 length = approvals.length;
            for (uint256 i = 0; i < length; ++i) {
                address token = approvals[i].token;
                address spender = approvals[i].spender;
                uint248 tokenId = approvals[i].tokenId;
                allowanceNFT[owner][token][tokenId][spender].amount = 0;
                emit LockdownNFT(owner, token, spender, tokenId);
            }
        }
    }

    /// @inheritdoc IAllowanceTransferNFT
    function invalidateNFTNonces(address token, uint256 tokenId, address spender, uint48 newNonce) external {
        uint48 oldNonce = allowanceNFT[msg.sender][token][tokenId][spender].nonce;

        if (newNonce <= oldNonce) revert InvalidNonce();

        // Limit the amount of nonces that can be invalidated in one transaction.
        unchecked {
            uint48 delta = newNonce - oldNonce;
            if (delta > type(uint16).max) revert ExcessiveInvalidation();
        }

        allowanceNFT[msg.sender][token][tokenId][spender].nonce = newNonce;
        emit NonceInvalidationNFT(msg.sender, token, spender, uint248(tokenId), newNonce, oldNonce);
    }

    /// @notice Sets the new values for amount, expiration, and nonce.
    /// @dev Will check that the signed nonce is equal to the current nonce and then incrememnt the nonce value by 1.
    /// @dev Emits a Permit event.
    function _updateNFTApproval(PermitNFTDetails memory details, address owner, address spender) private {
        uint248 tokenId = details.tokenId;
        uint48 nonce = details.nonce;
        address token = details.token;
        uint160 amount = details.amount;
        uint48 expiration = details.expiration;
        PackedAllowance storage allowed = allowanceNFT[owner][token][tokenId][spender];

        if (allowed.nonce != nonce) revert InvalidNonce();

        allowed.updateAll(amount, expiration, nonce);
        emit PermitNFT(owner, token, spender, tokenId, amount, expiration, nonce);
    }
}
