// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./library/TransferHelper.sol";
import "./interfaces/ICornerMarket.sol";
import {SignatureVerification} from "../permit2/libraries/SignatureVerification.sol";
import {SignatureExpired, InvalidNonce} from "../permit2/PermitErrors.sol";
import {IAllowanceTransferNFT} from "../permit2/interfaces/IAllowanceTransferNFT.sol";
import {EIP712Base} from "./EIP712Base.sol";

contract AgentManager is EIP712Base, AccessControl, ReentrancyGuard {
    using SignatureVerification for bytes;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    IAllowanceTransferNFT internal immutable permit2;
    bytes32 constant _WITHDRAW_BEHALF_TYPES = keccak256("WithdrawBehalf(uint48 nonce,uint256 deadline)");
    address public payToken;
    address public cornerMarket;
    uint public depositAmount;
    uint public fines;
    mapping(address => uint) public collaterals;
    mapping(address => bool) internal validateBook;
    mapping(address => uint48) public nonces;
    event Deposit(address account, address payToken, uint depositAmount);
    event Withdraw(address account, address payToken, uint withdrawAmount);
    event MarginDecrease(address account, uint decreaseAmount, uint remainAmount);
    event Take(address account, address token, uint takeAmount);
    event AgentStateChange(address account, bool isAgent);
    event DepositAmountChange(uint newDepositAmount, uint oldDepositAmount);

    constructor(address _payToken, uint _depositAmount, address _cornerMarket, address _permit2) EIP712Base("AgentManager") {
        permit2 = IAllowanceTransferNFT(_permit2);
        payToken = _payToken;
        depositAmount = _depositAmount;
        cornerMarket = _cornerMarket;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }
    function setDepositAmount(uint _depositAmount) external onlyRole(OPERATOR_ROLE) {
        require(depositAmount != _depositAmount, "deposit amount not change");
        emit DepositAmountChange(_depositAmount, depositAmount);
        depositAmount = _depositAmount;
    }

    function deposit() external {
        TransferHelper.safeTransferFrom(payToken, msg.sender, address(this), depositAmount);
        _deposit(msg.sender);
    }
    function _deposit(address user) internal nonReentrant {
        require(!validateBook[user], "already validated");
        collaterals[user] += depositAmount;
        validateBook[user] = true;
        emit Deposit(user, payToken, depositAmount);
        emit AgentStateChange(user, true);
    }

    function depositBehalf(address user, IAllowanceTransferNFT.PermitSingle calldata _permit, bytes calldata _signature) external {
        permit2.permit(user, _permit, _signature);
        permit2.transferFrom(user, address(this), uint160(depositAmount), _permit.details.token);
        _deposit(user);
    }
    
    function withdraw() external {
        _withdraw(msg.sender);
    }
    function _withdraw(address receiver) internal {
        require(ICornerMarket(cornerMarket).referrerExitTime(receiver) <= getBlockTimestamp(), "some coupon not reach end time");
        uint withdrableAmount = collaterals[receiver];
        collaterals[receiver] = 0;
        validateBook[receiver] = false;
        TransferHelper.safeTransfer(payToken, receiver, withdrableAmount);
        emit Withdraw(receiver, payToken, withdrableAmount);
        emit AgentStateChange(receiver, false);
    }

    function withdrawBehalf(address receiver, uint48 nonce, uint deadline, bytes calldata _signature) external {
        _signature.verify(_hashTypedData(getHash(nonce, deadline)), receiver);
        _updateNonce(nonce, receiver, deadline);
        _withdraw(receiver);
    }

    function _updateNonce(uint48 nonce, address owner, uint deadline) internal {
        if (getBlockTimestamp() > deadline) revert SignatureExpired(deadline);
        if (nonces[owner] != nonce) revert InvalidNonce();
        unchecked {
            nonces[owner] += 1;
        }
    }

    function getHash(uint48 nonce, uint deadline) internal pure returns(bytes32) {
        return
            keccak256(abi.encode(_WITHDRAW_BEHALF_TYPES, nonce, deadline));
    }

    function validate(address user) external view returns(bool) {
        return validateBook[user] || (depositAmount == 0);
    }
    function deduct(address account, uint amount) external onlyRole(OPERATOR_ROLE) {
        require(amount <= collaterals[account], "amount out of range");
        collaterals[account] -= amount;
        fines += amount;
        if (collaterals[account] == 0) {
            validateBook[account] = false;
            emit AgentStateChange(msg.sender, false);
        }
        emit MarginDecrease(account, amount, collaterals[account]);
    }

    function take(address token, uint amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) {
            TransferHelper.safeTransferETH(msg.sender, amount);
        } else {
            TransferHelper.safeTransfer(token, msg.sender, amount);
        }
        emit Take(msg.sender, token, amount);
    }

    function getBlockTimestamp() internal view returns (uint) {
        //solhint-disable-next-line not-rely-on-time
        return block.timestamp;
    }
}
