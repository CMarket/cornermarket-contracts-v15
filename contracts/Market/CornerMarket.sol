// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.17;
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./library/TransferHelper.sol";
import "./interfaces/IVoucher.sol";
import "./interfaces/IAgentManager.sol";
import {IAllowanceTransferNFT} from "../permit2/interfaces/IAllowanceTransferNFT.sol";
import {SignatureVerification} from "../permit2/libraries/SignatureVerification.sol";
import {SignatureExpired, InvalidNonce} from "../permit2/PermitErrors.sol";
import {PermitNFTHash} from "../permit2/libraries/PermitNFTHash.sol";
import {EIP712Base} from "./EIP712Base.sol";
import {SafeCast160} from "../permit2/libraries/SafeCast160.sol";

contract CornerMarketStorage {
    uint constant HUNDRED_PERCENT = 10000;
    uint constant MAX_REWARD_RATE = 2000;
    uint constant PROFIT_TYPE_BUY_REFERRER = 1;
    uint constant PROFIT_TYPE_COUPON_REFERRER = 2;
    uint constant PROFIT_TYPE_PLATFORM = 3;
    uint constant PROFIT_TYPE_MERCHANT = 4;
    uint constant PROFIT_TYPE_REFUND_TAX = 5;
    uint constant REFUND_TAX_RATE_MAX = 1000;
    enum CouponStatus{
        NOT_EXISTS,
        SELLING,
        BLOCK
    }
    enum RewardRateTarget{
        PLATFORM,
        BUYREFERRER,
        COUPONREFERRER
    }
    struct CouponMetadata{
        address owner;
        address payToken;
        uint pricePerCoupon;
        uint saleStart;
        uint saleEnd;
        uint useStart;
        uint useEnd;
        uint quota;
        uint refundTaxRate;
    }
    struct CouponMetadataStorage{
        address owner;
        address referrer;
        address payToken;
        uint pricePerCoupon;
        uint saleStart;
        uint saleEnd;
        uint useStart;
        uint useEnd;
        uint refundTaxRate;
        CouponStatus status;
    }
    struct CouponStatistics{
        uint quota;
        uint sold;
        uint refund;
        uint verified;
    }
    struct Withdrawable{
        mapping(address => uint) earnings;
        mapping(address => uint) withdrawn;
    }
    struct CreateBehalf{
        CouponMetadata coupon;
        uint48 nonce;
        uint256 sigDeadline;
    }
    Counters.Counter internal tokenId;
    mapping(uint => CouponMetadataStorage) public coupons;
    mapping(uint => CouponStatistics) public couponsQuota;
    mapping(address => bool) public supportTokens;
    mapping(address => Withdrawable) internal revenue;
    address public couponContract;
    uint public protectPeriod;
    uint public maxSalePeriod;
    uint public buyReferrerRewardRate;
    uint public couponReferrerRewardRate;
    uint public platformRewardRate;
    address public platformAccount;
    address public agentManager;
    address public buyReferrerRewardHolder;
    mapping(address => uint) public referrerExitTime;
    // mapping: user address => tokenId => amount
    mapping(address => mapping(uint => uint)) public liteKeeping;
    mapping(address => uint48) public liteNonce;
}

contract CornerMarket is CornerMarketStorage, EIP712Base, AccessControl, IERC1155Receiver, ReentrancyGuard {
    using Counters for Counters.Counter;
    using SignatureVerification for bytes;
    using PermitNFTHash for IAllowanceTransferNFT.PermitNFTSingle;
    IAllowanceTransferNFT internal immutable permit2;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant _COUPON_METADATA =
        keccak256("CouponMetadata(address owner,address payToken,uint256 pricePerCoupon,uint256 saleStart,uint256 saleEnd,uint256 useStart,uint256 useEnd,uint256 quota,uint256 refundTaxRate)");
    bytes32 public constant _CREATE_BEHALF_DATA =
        keccak256("CreateBehalf(CouponMetadata coupon,uint48 nonce,uint256 sigDeadline)CouponMetadata(address owner,address payToken,uint256 pricePerCoupon,uint256 saleStart,uint256 saleEnd,uint256 useStart,uint256 useEnd,uint256 quota,uint256 refundTaxRate)");
    event CouponCreated(uint tokenId, CouponMetadata meta, address referrer);
    event CouponStatusChange(uint tokenId, CouponStatus newStatus, CouponStatus oldStatus);
    event SupportTokenChange(address indexed token, bool newState, bool oldState);
    event BuyCoupon(address indexed payer, uint tokenId, uint amount, address payToken, uint payAmount, address indexed receiver);
    event Refund(uint tokenId, uint amount, address payer, address payToken, uint payAmount, address indexed receiver);
    event BuyerReferrer(address indexed buyer, address referrer, uint tokenId, uint amount);
    event BuyReferrerRewardHolderChange(address newHolder, address oldHolder);
    event ReferrerRewardRateChange(RewardRateTarget target, uint newRewardRate, uint oldRewardRate);
    event PlatformAccountChange(address indexed newPlatformAccount, address oldPlatformAccount);
    event Verified(uint tokenId, uint amount, address indexed fromAccount, address indexed payToken, uint totalAmount);
    event Settlement(uint tokenId, uint profitType, address indexed account, address payToken, uint sharedAmount);
    event WithdrawEarnings(address indexed account, address payToken, uint amount);
    event CouponSaleTimeExtended(uint tokenId, uint newEndTime, uint oldEndTime);
    event Take(address account, address token, uint takeAmount);
    event ReferrerExitTimeExtended(address account, uint newExitTime, uint oldExitTime);
    event AgentManagerChange(address newAgentManager, address oldAgentManager);
    event ProtectPeriodChange(uint newPeriod, uint oldPeriod);
    event MaxSalePeriodChange(uint newPeriod, uint oldPeriod);
    event WithdrawNFT(address indexed receiver, uint tokenId, uint amount);
    event DepositNFT(address indexed payer, uint tokenId, uint amount);

    constructor(address voucher, address _platformAccount, address referrerRewardHolder, address _permit2) EIP712Base("CornerMarket") {
        require(_platformAccount != address(0), "invalid platform account");
        require(referrerRewardHolder != address(0), "invalid platform account");
        permit2 = IAllowanceTransferNFT(_permit2);
        protectPeriod = 180 days;
        maxSalePeriod = 400 days;
        buyReferrerRewardRate = 0; // 0 = 0%   10000 = 100%
        couponReferrerRewardRate = 100; // 100 = 1%
        platformRewardRate = 100; // 100 = 1%
        couponContract = voucher;
        platformAccount = _platformAccount;
        buyReferrerRewardHolder = referrerRewardHolder;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }
    
    function createCoupon(CouponMetadata memory meta) external {
        _createCoupon(meta, msg.sender);
    }
    function _createCoupon(CouponMetadata memory meta, address agent) internal {
        require(meta.saleEnd > meta.saleStart, "sale time error");
        require(meta.useEnd > meta.useStart, "use time error");
        require(meta.saleEnd - meta.saleStart <= maxSalePeriod, "sale time error");
        require(meta.useEnd > meta.saleStart, "use time conflict with sale time");
        require(supportTokens[meta.payToken], "token not supported");
        require(IAgentManager(agentManager).validate(agent), "referrer is not a valid agent");
        require(meta.refundTaxRate <= REFUND_TAX_RATE_MAX, "exceed max refund tax rate");
        tokenId.increment();
        uint id = tokenId.current();
        coupons[id] = CouponMetadataStorage({
            owner: meta.owner,
            referrer: agent,
            payToken: meta.payToken,
            pricePerCoupon: meta.pricePerCoupon,
            saleStart: meta.saleStart,
            saleEnd: meta.saleEnd,
            useStart: meta.useStart,
            useEnd: meta.useEnd,
            refundTaxRate: meta.refundTaxRate,
            status: CouponStatus.SELLING
        });
        couponsQuota[id] = CouponStatistics({
            quota: meta.quota,
            sold: 0,
            refund: 0,
            verified: 0
        });

        emit CouponCreated(id, meta, agent);
        if (meta.useEnd > referrerExitTime[agent]) {
            emit ReferrerExitTimeExtended(agent, meta.useEnd, referrerExitTime[agent]);
            referrerExitTime[agent] = meta.useEnd;
        }
    }

    function createCouponBehalf(CreateBehalf memory behalf, address agent, bytes calldata _signature) external {
        _signature.verify(_hashTypedData(getHash(behalf)), agent);
        _updateNonce(behalf.nonce, agent, behalf.sigDeadline);
        _createCoupon(behalf.coupon, agent);
    }

    function blockCoupon(uint id) external onlyRole(OPERATOR_ROLE) {
        CouponMetadataStorage storage cms = coupons[id];
        require(cms.status == CouponStatus.SELLING, "invalid coupon");
        emit CouponStatusChange(id, CouponStatus.BLOCK, cms.status);
        cms.status = CouponStatus.BLOCK;
    }

    function setSupportToken(address token, bool support) external onlyRole(OPERATOR_ROLE) {
        require(supportTokens[token] != support, "not change");
        emit SupportTokenChange(token, support, supportTokens[token]);
        supportTokens[token] = support;
    }

    function setReferrerRewardRate(RewardRateTarget target, uint rate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(rate <= MAX_REWARD_RATE, "out of range");
        if (target == RewardRateTarget.BUYREFERRER) {
            emit ReferrerRewardRateChange(target, rate, buyReferrerRewardRate);
            buyReferrerRewardRate = rate;
        }
        if (target == RewardRateTarget.COUPONREFERRER) {
            emit ReferrerRewardRateChange(target, rate, couponReferrerRewardRate);
            couponReferrerRewardRate = rate;
        }
        if (target == RewardRateTarget.PLATFORM) {
            emit ReferrerRewardRateChange(target, rate, platformRewardRate);
            platformRewardRate = rate;
        }
    }

    function setPlatformAccount(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "invalid account");
        emit PlatformAccountChange(account, platformAccount);
        platformAccount = account;
    }
    function setAgentManager(address _agentManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_agentManager != address(0), "invalid address");
        emit AgentManagerChange(_agentManager, agentManager);
        agentManager = _agentManager;
    }

    function setBuyReferrerRewardHolder(address holder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(holder != address(0), "invalid address");
        emit BuyReferrerRewardHolderChange(holder, buyReferrerRewardHolder);
        buyReferrerRewardHolder = holder;
    }
    function setProtectPeriod(uint period) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit ProtectPeriodChange(period, protectPeriod);
        protectPeriod = period;
    }
    function setMaxSalePeriod(uint period) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(period >= 7 days, "invalid sale period");
        emit MaxSalePeriodChange(period, maxSalePeriod);
        maxSalePeriod = period;
    }
    function buyCoupon(uint id, uint amount, address receiver, address referrer, bool isLite) external {
        _buyCoupon(id, amount, receiver, referrer, address(0), isLite);
    }
    function _buyCoupon(uint id, uint amount, address receiver, address referrer, address from, bool isLite) internal nonReentrant {
        CouponMetadataStorage memory cms = coupons[id];
        CouponStatistics storage stats = couponsQuota[id];
        require(cms.status == CouponStatus.SELLING, "coupon not for sale");
        require(stats.sold + amount - stats.refund <= stats.quota, "exceed quota");
        require(getBlockTimestamp() >= cms.saleStart && getBlockTimestamp() <= cms.saleEnd, "invalid sale period");
        uint payAmount = cms.pricePerCoupon * amount;
        address realFrom = (from == address(0) ? msg.sender : from);
        if (from == address(0)) {
            TransferHelper.safeTransferFrom(cms.payToken, msg.sender, address(this), payAmount);
        } else {
            permit2.transferFrom(from, address(this), SafeCast160.toUint160(payAmount), cms.payToken);
        }
        emit BuyCoupon(realFrom, id, amount, cms.payToken, payAmount, receiver);
        stats.sold += amount;
        if (isLite) {
            liteKeeping[receiver][id] += amount;
        } else {
        IVoucher(couponContract).mint(receiver, id, amount, "");
        }
        emit BuyerReferrer(receiver, referrer, id, amount);
    }

    function buyCouponBehalf(uint id, uint amount, address receiver, address referrer, address from, bool isLite, IAllowanceTransferNFT.PermitSingle calldata _permit, bytes calldata _signature) external {
        permit2.permit(from, _permit, _signature);
        _buyCoupon(id, amount, receiver, referrer, from, isLite);
    }
    function getRevenue(address user, address token) external view returns(uint, uint) {
        return (revenue[user].earnings[token], revenue[user].withdrawn[token]);
    }

    function verifyCoupon(uint id, uint amount, bool isLite) external {
        if (isLite) {
            require(liteKeeping[msg.sender][id] >= amount, "insufficient coupon");
            liteKeeping[msg.sender][id] -= amount;
        } else {
        IVoucher(couponContract).safeTransferFrom(msg.sender, address(this), id, amount, "");
        IVoucher(couponContract).burn(address(this), id, amount);
        }
        _verifyCoupon(id, amount, msg.sender);
    }

    function _verifyCoupon(uint id, uint amount, address from) internal nonReentrant {
        CouponMetadataStorage memory cms = coupons[id];
        CouponStatistics storage stats = couponsQuota[id];
        require(getBlockTimestamp() >= cms.useStart && getBlockTimestamp() <= cms.useEnd, "out of use day ranges");
        uint totalAmount = cms.pricePerCoupon * amount;
        uint assignableAmount = totalAmount;
        emit Verified(id, amount, from, cms.payToken, totalAmount);
        if (buyReferrerRewardRate > 0) {
            uint referrerReward = totalAmount * buyReferrerRewardRate / HUNDRED_PERCENT;
            TransferHelper.safeTransfer(cms.payToken, buyReferrerRewardHolder, referrerReward);
            emit Settlement(id, PROFIT_TYPE_BUY_REFERRER, buyReferrerRewardHolder, cms.payToken, referrerReward);
            assignableAmount -= referrerReward;
        }
            if (couponReferrerRewardRate > 0) {
                uint referrerReward = totalAmount * couponReferrerRewardRate / HUNDRED_PERCENT;
                address referrerAddress = cms.referrer;
                if (referrerAddress == address(0)) {
                    referrerAddress = platformAccount;
                }
                revenue[referrerAddress].earnings[cms.payToken] += referrerReward;
                _withdraw(cms.payToken, referrerAddress);
                emit Settlement(id, PROFIT_TYPE_COUPON_REFERRER, referrerAddress, cms.payToken, referrerReward);
                assignableAmount -= referrerReward;
        }
        if (platformRewardRate > 0) {
            uint referrerReward = totalAmount * platformRewardRate / HUNDRED_PERCENT;
            revenue[platformAccount].earnings[cms.payToken] += referrerReward;
            _withdraw(cms.payToken, platformAccount);
            emit Settlement(id, PROFIT_TYPE_PLATFORM, platformAccount, cms.payToken, referrerReward);
            assignableAmount -= referrerReward;
        }
        //merchant get paid
        revenue[cms.owner].earnings[cms.payToken] += assignableAmount;
        _withdraw(cms.payToken, cms.owner);
        emit Settlement(id, PROFIT_TYPE_MERCHANT, cms.owner, cms.payToken, assignableAmount);

        stats.verified += amount;
    }

    function verifyCouponBehalf(address from, bool isLite, IAllowanceTransferNFT.PermitNFTSingle calldata _permit, bytes calldata _signature) external {
        if (isLite) {
            require(liteKeeping[from][_permit.details.tokenId] >= _permit.details.amount, "insufficient coupon");
            _signature.verify(_hashTypedData(_permit.hash()), from);
            liteKeeping[from][_permit.details.tokenId] -= _permit.details.amount;
            _updateNonce(_permit.details.nonce, from, _permit.sigDeadline);
        } else {
        permit2.permitNFT(from, _permit, _signature);
        permit2.transferNFTFrom(from, address(this), _permit.details.tokenId, _permit.details.typeId, _permit.details.amount, _permit.details.token);
        IVoucher(couponContract).burn(address(this), _permit.details.tokenId, _permit.details.amount);
        }
        _verifyCoupon(_permit.details.tokenId, _permit.details.amount, from);
    }

    function refundCoupon(uint id, uint amount, address receiver, bool isLite) external {
        if (isLite) {
            require(liteKeeping[msg.sender][id] >= amount, "insufficient coupon");
            liteKeeping[msg.sender][id] -= amount;
        } else {
        IVoucher(couponContract).safeTransferFrom(msg.sender, address(this), id, amount, "");
        IVoucher(couponContract).burn(address(this), id, amount);
        }
        _refundCoupon(id, amount, receiver, msg.sender);
    }
    function _refundCoupon(uint id, uint amount, address receiver, address from) internal nonReentrant {
        CouponMetadataStorage memory cms = coupons[id];
        CouponStatistics storage stats = couponsQuota[id];

        uint refundAmount = cms.pricePerCoupon * amount;
        stats.refund += amount;
        if (cms.refundTaxRate > 0) {
            uint tax = refundAmount * cms.refundTaxRate / HUNDRED_PERCENT;
            TransferHelper.safeTransfer(cms.payToken, platformAccount, tax);
            emit Settlement(id, PROFIT_TYPE_REFUND_TAX, platformAccount, cms.payToken, tax);
            refundAmount = refundAmount - tax;
        }
        TransferHelper.safeTransfer(cms.payToken, receiver, refundAmount);

        emit Refund(id, amount, from, cms.payToken, refundAmount, receiver);
        }
    function refundCouponBehalf(address receiver, bool isLite, IAllowanceTransferNFT.PermitNFTSingle calldata _permit, bytes calldata _signature) external {
        if (isLite) {
            require(liteKeeping[receiver][_permit.details.tokenId] >= _permit.details.amount, "insufficient coupon");
            _signature.verify(_hashTypedData(_permit.hash()), receiver);
            liteKeeping[receiver][_permit.details.tokenId] -= _permit.details.amount;
            _updateNonce(_permit.details.nonce, receiver, _permit.sigDeadline);
        } else {
        permit2.permitNFT(receiver, _permit, _signature);
        permit2.transferNFTFrom(receiver, address(this), _permit.details.tokenId, _permit.details.typeId, _permit.details.amount, _permit.details.token);
        IVoucher(couponContract).burn(address(this), _permit.details.tokenId, _permit.details.amount);
        }
        _refundCoupon(_permit.details.tokenId, _permit.details.amount, receiver, receiver);
    }
    function invalidateNFTNonces() external {
        unchecked {
            liteNonce[msg.sender] += 1;
        }
    }
    function _updateNonce(uint48 nonce, address owner, uint deadline) internal {
        if (getBlockTimestamp() > deadline) revert SignatureExpired(deadline);
        if (liteNonce[owner] != nonce) revert InvalidNonce();
        unchecked {
            liteNonce[owner] += 1;
        }
    }
    function withdrawNFT(uint id, uint amount) external {
        require(liteKeeping[msg.sender][id] >= amount, "insufficient NFT");
        liteKeeping[msg.sender][id] -= amount;
        IVoucher(couponContract).mint(msg.sender, id, amount, "");
        emit WithdrawNFT(msg.sender, id, amount);
    }
    function depositNFT(uint id, uint amount) external {
        IVoucher(couponContract).safeTransferFrom(msg.sender, address(this), id, amount, "");
        IVoucher(couponContract).burn(address(this), id, amount);
        liteKeeping[msg.sender][id] += amount;
        emit DepositNFT(msg.sender, id, amount);
    }

    function _withdraw(address token, address account) internal {
        uint withdrableAmount = revenue[account].earnings[token] - revenue[account].withdrawn[token];
        if (withdrableAmount > 0) {
            revenue[account].withdrawn[token] = revenue[account].earnings[token];
            TransferHelper.safeTransfer(token, account, withdrableAmount);
            emit WithdrawEarnings(account, token, withdrableAmount);
        }
    }
    

    function getBlockTimestamp() internal view returns (uint) {
        //solhint-disable-next-line not-rely-on-time
        return block.timestamp;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public override(AccessControl, IERC165) virtual view returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    function getHash(CreateBehalf memory behalf) internal pure returns(bytes32) {
        bytes32 couponHash = _hashCouponMetadata(behalf.coupon);
        return
            keccak256(abi.encode(_CREATE_BEHALF_DATA, couponHash, behalf.nonce, behalf.sigDeadline));
    }
    function _hashCouponMetadata(CouponMetadata memory coupon) private pure returns (bytes32) {
        return keccak256(abi.encode(_COUPON_METADATA, coupon));
    }
    function take(address token, uint amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) {
            TransferHelper.safeTransferETH(msg.sender, amount);
        } else {
            TransferHelper.safeTransfer(token, msg.sender, amount);
        }
        emit Take(msg.sender, token, amount);
    }
    function currentId() external view returns(uint) {
        return tokenId.current();
    }
}