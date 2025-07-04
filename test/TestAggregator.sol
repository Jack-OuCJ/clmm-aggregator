pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "../contracts/core/libraries/TickMath.sol";
import "../contracts/periphery/SwapRouter.sol";
import {CLPool} from "../contracts/core/CLPool.sol";
import {LiquidityManagement} from "../contracts/periphery/base/LiquidityManagement.sol";
import {SwapRouter} from "../contracts/periphery/SwapRouter.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {Token} from "../contracts/core/utils/Token.sol";
import "lib/forge-std/src/console.sol";

contract AggregatorTest is Test {
    address public owner;
    address public supplier1;
    address public trader1;
    address public trader2;

    uint256 constant ZERO = 0;
    uint256 constant ONE = 1 ether;
    uint256 constant FIVE = 5 ether;
    uint256 constant TEN = 10 ether;
    uint256 constant FEES = 2000;
    uint256 constant INITIAL_TOKENS = 10000 ether;
    uint256 constant TOKEN_AMOUNT = 5000 ether;
    int24 constant TICK_LOWER = -887200;
    int24 constant TICK_UPPER = 887200;
    SwapRouter swapRouter = SwapRouter(payable(vm.envAddress("ROUTER")));
    ICLFactory factory = ICLFactory(vm.envAddress("FACTORY"));
    ICLPool pool = ICLPool(vm.envAddress("CLPOOL"));
    Token tokenA = Token(vm.envAddress("TokenA"));
    Token tokenB = Token(vm.envAddress("TokenB"));
    Token tokenC = Token(vm.envAddress("TokenC"));
    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.rememberKey(deployPrivateKey);

    function setUp() public {
        owner     = address(this);
        supplier1 = address(1);
        trader1   = address(2);
        trader2  = address(3);

        vm.label(supplier1, "supplier1");
        vm.label(trader1, "trader1");
        vm.label(trader2, "trader2");

        vm.deal(owner, INITIAL_TOKENS);
        vm.deal(supplier1, INITIAL_TOKENS);
        vm.deal(trader1, INITIAL_TOKENS);
        vm.deal(trader2, INITIAL_TOKENS);
        uint256 balance = tokenA.balanceOf(address(tokenA));
        console.log("balance", balance);
        vm.prank(deployerAddress);
        tokenA.transfer(supplier1, TOKEN_AMOUNT);
        vm.prank(deployerAddress);
        tokenB.transfer(supplier1, TOKEN_AMOUNT);
        vm.prank(deployerAddress);
        tokenC.transfer(supplier1, TOKEN_AMOUNT);
        vm.prank(supplier1);
        tokenA.approve(address(swapRouter), TOKEN_AMOUNT);
        vm.prank(supplier1);
        tokenB.approve(address(swapRouter), TOKEN_AMOUNT);
        vm.prank(supplier1);
        tokenC.approve(address(swapRouter), TOKEN_AMOUNT);
    }

    function _initializePool() internal {
        uint256 amount0Desired = 1000 ether;
        uint256 amount1Desired = 1000 ether;

        address poolAddress = factory.getPool(address(tokenA), address(tokenB), 10);
        vm.prank(supplier1);
        // The boundary values of tick must be integer multiples of tickSpacing.
        // Token0 must be less than token1.
        (address token0, address token1) = address(tokenA) < address(tokenB)?
            (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));
        (uint128 liquidity, uint256 amount0, uint256 amount1) = swapRouter.addLiquidity(
            LiquidityManagement.AddLiquidityParams({
                poolAddress: poolAddress,
                poolKey: PoolAddress.PoolKey({
                    token0: token0,
                    token1: token1,
                    tickSpacing: 10
                }),
                recipient: address(supplier1),
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0
            })
        );

        console.log("A/B Liquidity:", uint256(liquidity) / 1 ether);
        console.log("Amount0:", amount0 / 1 ether);
        console.log("Amount1:", amount1 / 1 ether);

        poolAddress = factory.getPool(address(tokenB), address(tokenC), 10);
        vm.prank(supplier1);
        (token0, token1) = address(tokenB) < address(tokenC)?
            (address(tokenB), address(tokenC)) : (address(tokenC), address(tokenB));
        (liquidity, amount0, amount1) = swapRouter.addLiquidity(
            LiquidityManagement.AddLiquidityParams({
                poolAddress: poolAddress,
                poolKey: PoolAddress.PoolKey({
                    token0: token0,
                    token1: token1,
                    tickSpacing: 10
                }),
                recipient: address(supplier1),
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0
            })
        );

        console.log("B/C Liquidity:", uint256(liquidity));
        console.log("Amount0:", amount0);
        console.log("Amount1:", amount1);

        poolAddress = factory.getPool(address(tokenA), address(tokenC), 10);
        vm.prank(supplier1);
        (token0, token1) = address(tokenA) < address(tokenC)?
            (address(tokenA), address(tokenC)) : (address(tokenC), address(tokenA));
        (liquidity, amount0, amount1) = swapRouter.addLiquidity(
            LiquidityManagement.AddLiquidityParams({
                poolAddress: poolAddress,
                poolKey: PoolAddress.PoolKey({
                    token0: token0,
                    token1: token1,
                    tickSpacing: 10
                }),
                recipient: address(supplier1),
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0
            })
        );

        console.log("A/C Liquidity:", uint256(liquidity));
        console.log("Amount0:", amount0);
        console.log("Amount1:", amount1);
    }

    function testOptimizeSwap() public  {
        _initializePool();
        address poolAB = factory.getPool(address(tokenA), address(tokenB), 10);
        address poolBC = factory.getPool(address(tokenB), address(tokenC), 10);
        address poolAC = factory.getPool(address(tokenA), address(tokenC), 10);
        SwapRouter.OptimizedSwapParams memory params;
        params.srcToken = IERC20(address(tokenA));
        params.dstToken = IERC20(address(tokenC));
        params.amountIn = 10 * 1 ether;
        params.amountOutMinimum = 0;
        params.sqrtPriceLimitX96 = 0;
        params.recipient = supplier1;

        vm.prank(supplier1);
        uint256 amountOut = swapRouter.optimizedExactInput(params);
        console.log("amountOut = ", amountOut / 1 ether);
    }

    function testSingleSwap() public {
        _initializePool();

        SwapRouter.ExactInputSingleParams memory params;
        params.tokenIn = address(tokenA);
        params.tokenOut = address(tokenC);
        params.tickSpacing = 10;
        params.amountIn = 10 * 1 ether;
        params.amountOutMinimum = 0;
        params.sqrtPriceLimitX96 = 0;
        params.recipient = trader1;

        vm.prank(supplier1);
        uint256 amountOut = swapRouter.exactInputSingle(params);
        console.log("a->c amountOut = ", amountOut / 1 ether);

        params.tokenIn = address(tokenA);
        params.tokenOut = address(tokenB);
        params.tickSpacing = 10;
        params.amountIn = 10 * 1 ether;
        params.amountOutMinimum = 0;
        params.sqrtPriceLimitX96 = 0;
        params.recipient = trader1;

        vm.prank(supplier1);
        amountOut = swapRouter.exactInputSingle(params);
        console.log("a->b amountOut = ", amountOut / 1 ether);

        params.tokenIn = address(tokenB);
        params.tokenOut = address(tokenC);
        params.tickSpacing = 10;
        params.amountIn = 10 * 1 ether;
        params.amountOutMinimum = 0;
        params.sqrtPriceLimitX96 = 0;
        params.recipient = trader1;

        vm.prank(supplier1);
        amountOut = swapRouter.exactInputSingle(params);
        console.log("b->c amountOut = ", amountOut / 1 ether);
    }
}