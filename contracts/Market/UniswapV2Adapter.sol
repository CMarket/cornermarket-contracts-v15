// SPDX-License-Identifier: CC0-1.0
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./library/TransferHelper.sol";
import "./interfaces/ICornerMarket.sol";
import "./interfaces/IUniswapV2Router.sol";
import {IAllowanceTransferNFT} from "../permit2/interfaces/IAllowanceTransferNFT.sol";

contract UniswapV2Adapter is Ownable {
    uint constant ONE_HUNDRED_RATE = 10000;
    ICornerMarket public immutable cornermarket;
    IAllowanceTransferNFT internal immutable permit2;
    IUniswapV2Router dexRouter;
    uint public feeRate;

    event FeeRateChange(uint newRate, uint oldRate);
    event BuyCoupon(uint id, uint amount, address receiver, address payToken, uint payTokenAmount);

    constructor(address _cornermarket, address _permit, address dex, uint _feeRate) {
        cornermarket = ICornerMarket(_cornermarket);
        permit2 = IAllowanceTransferNFT(_permit);
        dexRouter = IUniswapV2Router(dex);
        feeRate = _feeRate;
    }

    function setFeeRate(uint newRate) external onlyOwner {
        require(newRate < ONE_HUNDRED_RATE, "feeRate too high");
        emit FeeRateChange(newRate, feeRate);
        feeRate = newRate;
    }

    function estimateInfo(uint id, uint amount, address userPayToken) external view returns (uint payAmount,uint fee,uint slippage){
        (,,address couponPayToken,uint pricePerCoupon,,,,,,) = cornermarket.coupons(id);
        uint requiredAmount = pricePerCoupon * amount;
        uint requiredAmountWithFee = requiredAmount * (ONE_HUNDRED_RATE + feeRate) / ONE_HUNDRED_RATE;
        address[] memory path = new address[](2);
        path[0] = userPayToken;
        path[1] = couponPayToken;
        payAmount = dexRouter.getAmountsIn(requiredAmountWithFee, path)[0];
        fee = requiredAmountWithFee - requiredAmount;
        IUniswapV2Factory factory = IUniswapV2Factory(dexRouter.factory());
        address pair = factory.getPair(userPayToken,couponPayToken);
        require(pair != address(0),"pair does not exist");
        IUniswapV2Pair uniPair = IUniswapV2Pair(pair);
        (uint reserves0,uint reserves1,) = uniPair.getReserves();
        uint couponPayReserves;
        uint userPayReserves;
        if( couponPayToken < userPayToken ){
            couponPayReserves = reserves0;
            userPayReserves = reserves1;
        }else {
            couponPayReserves = reserves1;
            userPayReserves = reserves0;
        }
        // requiredAmountWithFee / midAmount  =        couponPayReserves / userPayReserves
        uint midAmount = requiredAmountWithFee * userPayReserves / couponPayReserves;
        require(midAmount <= payAmount,"amount error");
        slippage = (payAmount - midAmount) * 1e18 / midAmount;
    }

    function buyCoupon(uint id, uint amount, address receiver, IAllowanceTransferNFT.PermitSingle calldata _permit, bytes calldata _signature) external {
        permit2.permit(receiver, _permit, _signature);
        (,,address payToken,uint pricePerCoupon,,,,,,) = cornermarket.coupons(id);
        uint requiredAmount = pricePerCoupon * amount;
        uint requiredAmountWithFee = requiredAmount * (ONE_HUNDRED_RATE + feeRate) / ONE_HUNDRED_RATE;
        address[] memory path = new address[](2);
        path[0] = _permit.details.token;
        path[1] = payToken;
        uint requiredAmountIn = dexRouter.getAmountsIn(requiredAmountWithFee, path)[0];
        // require(payToken == _permit.details.token, "token not match");
        require(requiredAmountIn <= _permit.details.amount, "insufficient approve");
        permit2.transferFrom(receiver, address(this), uint160(requiredAmountIn), _permit.details.token);
        IERC20(_permit.details.token).approve(address(dexRouter), requiredAmountIn);
        emit BuyCoupon(id, amount, receiver, _permit.details.token, requiredAmountIn);
        dexRouter.swapTokensForExactTokens(requiredAmountWithFee, requiredAmountIn, path, address(this), block.timestamp + 1000);
        IERC20(payToken).approve(address(cornermarket), requiredAmount);
        cornermarket.buyCoupon(id, amount, receiver, address(0), true);
    }

    function withdrawFee(address token) external onlyOwner {
        uint balance = IERC20(token).balanceOf(address(this));
        TransferHelper.safeTransfer(token, msg.sender, balance);
    }
}