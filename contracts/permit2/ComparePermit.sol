// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IAllowanceTransfer} from"./interfaces/IAllowanceTransfer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "hardhat/console.sol";
// IAllowanceTransfer(params.permit2)

contract ComparePermit {
    IAllowanceTransfer internal immutable permit2;

    constructor(address _permit2) {
        permit2 = IAllowanceTransfer(_permit2);
    }

    function permit2TransferFrom(address from, address to, uint160 amount, IAllowanceTransfer.PermitSingle calldata _permit, bytes calldata _signature) external {
        // permit2.transferFrom(from, to, amount, token);
        permit2.permit(from, _permit, _signature);
        permit2.transferFrom(from, to, amount, _permit.details.token);
    }

    // function permit2TransferFrom(IAllowanceTransfer.AllowanceTransferDetails[] memory batchDetails, address owner) internal {
    //     uint256 batchLength = batchDetails.length;
    //     for (uint256 i = 0; i < batchLength; ++i) {
    //         if (batchDetails[i].from != owner) revert FromAddressIsNotOwner();
    //     }
    //     PERMIT2.transferFrom(batchDetails);
    // }

    function permitTransferFrom(address token, address from, address to, uint160 amount,uint256 deadline,uint8 v,bytes32 r,bytes32 s) external {
        IERC20Permit(token).permit(from, address(this), amount, deadline, v, r, s);
        IERC20(token).transferFrom(from, to, amount);
    }

    function commonTransferFrom(address token, address from, address to, uint160 amount) external {
        IERC20(token).transferFrom(from, to, amount);
    }

}