// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "./base/LiquidityManagement.sol";
import "./base/PeripheryImmutableState.sol";

import "./base/PeripheryPaymentsWithFee.sol";
import "./base/PeripheryValidation.sol";
import "./base/SelfPermit.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/external/IWETH9.sol";
import "./libraries/CallbackValidation.sol";
import "./libraries/Path.sol";
import "./libraries/PoolAddress.sol";
import "contracts/core/interfaces/ICLPool.sol";
import "contracts/core/libraries/SafeCast.sol";
import "contracts/core/libraries/TickMath.sol";
import {Address} from "../../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title CL Swap Router
/// @notice Router for stateless execution of swaps against CL
contract SwapRouter is
    ISwapRouter,
    PeripheryImmutableState,
    PeripheryValidation,
    PeripheryPaymentsWithFee,
    SelfPermit,
    LiquidityManagement
{
    using Path for bytes;
    using SafeCast for uint256;

    /// @dev Used as the placeholder value for amountInCached, because the computed amount in for an exact output swap
    /// can never actually be this value
    uint256 private constant DEFAULT_AMOUNT_IN_CACHED = type(uint256).max;

    /// @dev Transient storage variable used for returning the computed amount in for an exact output swap.
    uint256 private amountInCached = DEFAULT_AMOUNT_IN_CACHED;

    IOracle public oracle;

    constructor(address _factory, address _WETH9, address _oracleAddress) PeripheryImmutableState(_factory, _WETH9) {
        oracle = IOracle(_oracleAddress);
    }

    /// @dev Returns the pool for the given token pair and fee. The pool contract may or may not exist.
    function getPool(address tokenA, address tokenB, int24 tickSpacing) private view returns (ICLPool) {
        return ICLPool(PoolAddress.computeAddress(factory, PoolAddress.getPoolKey(tokenA, tokenB, tickSpacing)));
    }

    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    /// @inheritdoc ICLSwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external override {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        (address tokenIn, address tokenOut, int24 tickSpacing) = data.path.decodeFirstPool();
        CallbackValidation.verifyCallback(factory, tokenIn, tokenOut, tickSpacing);

        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0 ? (tokenIn < tokenOut, uint256(amount0Delta)) : (tokenOut < tokenIn, uint256(amount1Delta));
        if (isExactInput) {
            pay(tokenIn, data.payer, msg.sender, amountToPay);
        } else {
            // either initiate the next swap or pay
            if (data.path.hasMultiplePools()) {
                data.path = data.path.skipToken();
                exactOutputInternal(amountToPay, msg.sender, 0, data);
            } else {
                amountInCached = amountToPay;
                tokenIn = tokenOut; // swap in/out because exact output swaps are reversed
                pay(tokenIn, data.payer, msg.sender, amountToPay);
            }
        }
    }

    /// @dev Performs a single exact input swap
    function exactInputInternal(
        uint256 amountIn,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountOut) {
        // allow swapping to the router address with address 0
        if (recipient == address(0)) recipient = address(this);

        (address tokenIn, address tokenOut, int24 tickSpacing) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0, int256 amount1) = getPool(tokenIn, tokenOut, tickSpacing).swap(
            recipient,
            zeroForOne,
            amountIn.toInt256(),
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            abi.encode(data)
        );

        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    /// @inheritdoc ISwapRouter
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        amountOut = exactInputInternal(
            params.amountIn,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({
                path: abi.encodePacked(params.tokenIn, params.tickSpacing, params.tokenOut),
                payer: msg.sender
            })
        );
        require(amountOut >= params.amountOutMinimum, "Too little received");
        refundETH();
    }

    /// @inheritdoc ISwapRouter
    function exactInput(ExactInputParams memory params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        address payer = msg.sender; // msg.sender pays for the first hop

        while (true) {
            bool hasMultiplePools = params.path.hasMultiplePools();

            // the outputs of prior swaps become the inputs to subsequent ones
            params.amountIn = exactInputInternal(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient, // for intermediate swaps, this contract custodies
                0,
                SwapCallbackData({
                    path: params.path.getFirstPool(), // only the first pool in the path is necessary
                    payer: payer
                })
            );

            // decide whether to continue or terminate
            if (hasMultiplePools) {
                payer = address(this); // at this point, the caller has paid
                params.path = params.path.skipToken();
            } else {
                amountOut = params.amountIn;
                break;
            }
        }

        require(amountOut >= params.amountOutMinimum, "Too little received");
        refundETH();
    }

    /// @dev Performs a single exact output swap
    function exactOutputInternal(
        uint256 amountOut,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountIn) {
        // allow swapping to the router address with address 0
        if (recipient == address(0)) recipient = address(this);

        (address tokenOut, address tokenIn, int24 tickSpacing) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0Delta, int256 amount1Delta) = getPool(tokenIn, tokenOut, tickSpacing).swap(
            recipient,
            zeroForOne,
            -amountOut.toInt256(),
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            abi.encode(data)
        );

        uint256 amountOutReceived;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));
        // it's technically possible to not receive the full output amount,
        // so if no price limit has been specified, require this possibility away
        if (sqrtPriceLimitX96 == 0) require(amountOutReceived == amountOut);
    }

    /// @inheritdoc ISwapRouter
    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountIn)
    {
        // avoid an SLOAD by using the swap return data
        amountIn = exactOutputInternal(
            params.amountOut,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({
                path: abi.encodePacked(params.tokenOut, params.tickSpacing, params.tokenIn),
                payer: msg.sender
            })
        );

        require(amountIn <= params.amountInMaximum, "Too much requested");
        // has to be reset even though we don't use it in the single hop case
        amountInCached = DEFAULT_AMOUNT_IN_CACHED;
        refundETH();
    }

    /// @inheritdoc ISwapRouter
    function exactOutput(ExactOutputParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountIn)
    {
        // it's okay that the payer is fixed to msg.sender here, as they're only paying for the "final" exact output
        // swap, which happens first, and subsequent swaps are paid for within nested callback frames
        exactOutputInternal(
            params.amountOut, params.recipient, 0, SwapCallbackData({path: params.path, payer: msg.sender})
        );

        amountIn = amountInCached;
        require(amountIn <= params.amountInMaximum, "Too much requested");
        amountInCached = DEFAULT_AMOUNT_IN_CACHED;
        refundETH();
    }

    function findBestExchangePath(IERC20 srcToken, IERC20 dstToken, uint256 amountIn) external returns (address[] memory path, uint256 amountOut) {
        require(amountIn > 0, "Invalid amount");

        uint256 bestRate = 0;
        address[] memory bestPath;

        (uint256 rate, address[] memory path, int24 bestSpacing) = oracle.findBestRate(srcToken, dstToken);

        uint256 amountOutThroughConnector = amountIn * rate;
        amountOut = bestRate * amountIn;
        return (bestPath, amountOut);
    }

    struct OptimizedSwapParams {
        IERC20 srcToken;
        IERC20 dstToken;
        uint256 amountIn;
        uint256 amountOutMinimum;
        address recipient;
        uint256 deadline;
        uint160 sqrtPriceLimitX96;
    }

    function optimizedExactInput(OptimizedSwapParams memory params)
        external
        payable
        returns (uint256 amountOut)
    {
        address payer = msg.sender;
        (uint256 rate, address[] memory path, int24 bestSpacing) = oracle.findBestRate(
            params.srcToken,
            params.dstToken
        );

        require(path.length > 0, "No path found");
        bytes memory encodedPath;

        if (path[2] != address(0)) {
            encodedPath = abi.encodePacked(address(path[0]), int24(bestSpacing), address(path[1]));
            params.amountIn = exactInputInternal(
                params.amountIn,
                address(this),
                params.sqrtPriceLimitX96,
                SwapCallbackData({
                    path: encodedPath,
                    payer: payer
                })
            );

            payer = address(this); // at this point, the caller has paid
            encodedPath = abi.encodePacked(address(path[1]), int24(bestSpacing), address(path[2]));

            amountOut = exactInputInternal(
                params.amountIn,
                params.recipient,
                params.sqrtPriceLimitX96,
                SwapCallbackData({
                    path: encodedPath,
                    payer: payer
                })
            );
        } else {
            encodedPath = abi.encodePacked(address(path[0]), int24(bestSpacing), address(path[1]));
            amountOut = exactInputInternal(
                params.amountIn,
                params.recipient,
                params.sqrtPriceLimitX96,
                SwapCallbackData({
                    path: encodedPath,
                    payer: payer
                })
            );
        }

        require(amountOut >= params.amountOutMinimum, "Too little received");
        refundETH();
    }
}
