// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;
import "../../permit2/interfaces/IAllowanceTransferNFT.sol";

interface ICornerMarket {
    function referrerExitTime( address  ) external view returns (uint256 ) ;
    function buyCoupon( uint256 id,uint256 amount,address receiver,address referrer,bool isLite ) external   ;
    function buyCouponBehalf( uint256 id,uint256 amount,address receiver,address referrer,address from,bool isLite,IAllowanceTransfer.PermitSingle memory _permit,bytes memory _signature ) external   ;
    function refundCoupon( uint256 id,uint256 amount,address receiver,bool isLite ) external   ;
    function refundCouponBehalf( address receiver,bool isLite,IAllowanceTransferNFT.PermitNFTSingle memory _permit,bytes memory _signature ) external   ;
    function verifyCoupon( uint256 id,uint256 amount,bool isLite ) external   ;
    function verifyCouponBehalf( address from,bool isLite,IAllowanceTransferNFT.PermitNFTSingle memory _permit,bytes memory _signature ) external   ;
    function couponContract(  ) external view returns (address ) ;
    function coupons( uint256  ) external view returns (address owner, address referrer, address payToken, uint256 pricePerCoupon, uint256 saleStart, uint256 saleEnd, uint256 useStart, uint256 useEnd, uint256 refundTaxRate, uint8 status) ;
}