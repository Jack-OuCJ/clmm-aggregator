// SPDX-License-Identifier: MIT

pragma solidity =0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IUniswapV3Pool.sol";
import "./libraries/OraclePrices.sol";
import "@openzeppelin/contracts/utils//EnumerableSet.sol";
import {CLPool} from "../core/CLPool.sol";
import {PoolAddress} from "./libraries/PoolAddress.sol";

contract UniswapV3LikeOracle is IOracle {
    using OraclePrices for OraclePrices.Data;
    using Math for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    event ConnectorAdded(IERC20 connector);
    event ConnectorRemoved(IERC20 connector);
    event ConnectorAlreadyAdded(IERC20 connector);

    IERC20 private constant _NONE = IERC20(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);
    int24 private constant _TICK_STEPS = 2;

    uint256 public immutable SUPPORTED_TICKSPACING_COUNT;
    address public immutable FACTORY;
    bytes32 public immutable INITCODE_HASH;
    EnumerableSet.AddressSet private _connectors;
    int24[10] public tickSpacings;

    constructor(address _factory, bytes32 _initcodeHash, int24[] memory _tickSpacings, IERC20[] memory existingConnectors) {
        FACTORY = _factory;
        INITCODE_HASH = _initcodeHash;
        SUPPORTED_TICKSPACING_COUNT = _tickSpacings.length;
        for (uint256 i = 0; i < _tickSpacings.length; i++) {
            tickSpacings[i] = _tickSpacings[i];
        }
        for (uint256 i = 0; i < existingConnectors.length; i++) {
            if(!_connectors.add(address(existingConnectors[i]))) emit ConnectorAlreadyAdded(existingConnectors[i]);
            emit ConnectorAdded(existingConnectors[i]);
        }
    }

    function getRate(IERC20 srcToken, IERC20 dstToken, IERC20 connector, uint256 thresholdFilter) external override returns (uint256 rate, uint256 weight) {
        OraclePrices.Data memory ratesAndWeights;
        if (connector == _NONE) {
            ratesAndWeights = OraclePrices.init(SUPPORTED_TICKSPACING_COUNT);
            for (uint256 i = 0; i < SUPPORTED_TICKSPACING_COUNT; i++) {
                (uint256 rate0, uint256 w) = _getRate(srcToken, dstToken, tickSpacings[i]);
                ratesAndWeights.append(OraclePrices.OraclePrice(rate0, w));
            }
        } else {
            ratesAndWeights = OraclePrices.init(SUPPORTED_TICKSPACING_COUNT**2);
            for (uint256 i = 0; i < SUPPORTED_TICKSPACING_COUNT; i++) {
                (uint256 rate0, uint256 w0) = _getRate(srcToken, connector, tickSpacings[i]);
                if (rate0 == 0 || w0 == 0) {
                    continue;
                }
                for (uint256 j = 0; j < SUPPORTED_TICKSPACING_COUNT; j++) {
                    (uint256 rate1, uint256 w1) = _getRate(connector, dstToken, tickSpacings[j]);
                    if (rate1 == 0 || w1 == 0) {
                        continue;
                    }
                    ratesAndWeights.append(OraclePrices.OraclePrice(SafeMath.mul(rate0, rate1)/1e18, Math.min(w0, w1)));
                }
            }
        }
        return ratesAndWeights.getRateAndWeight(thresholdFilter);
    }

    function _getRate(IERC20 srcToken, IERC20 dstToken, int24 tickSpacing) internal returns (uint256 rate, uint256 liquidity) {
        (IERC20 token0, IERC20 token1) = srcToken < dstToken ? (srcToken, dstToken) : (srcToken, dstToken);
        address pool = PoolAddress.computeAddress(
            FACTORY,
            PoolAddress.getPoolKey(address(token0), address(token1), tickSpacing)
        );

        if (!Address.isContract(pool)) { // !pool.isContract()
            return (0, 0);
        }
        liquidity = CLPool(pool).liquidity();
        if (liquidity == 0) {
            return (0, 0);
        }
        (uint256 sqrtPriceX96, int24 tick) = _currentState(pool);
        int24 tickSpacing = CLPool(pool).tickSpacing();
        tick = tick / tickSpacing * tickSpacing;

        if (srcToken == token1) {
            rate = (((1e18 * sqrtPriceX96) >> 96) * sqrtPriceX96) >> 96;
        } else {
            rate = (1e18 << 192) / sqrtPriceX96 / sqrtPriceX96;
        }
    }

    function _getPool(address token0, address token1, int24 tickSpacing) internal view virtual returns (address) {
        return address(uint160(uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        FACTORY,
                        keccak256(abi.encode(token0, token1, tickSpacing)),
                        INITCODE_HASH
                    )
                )
            )));
    }

    function _currentState(address pool) internal view virtual returns (uint256 sqrtPriceX96, int24 tick) {
        (sqrtPriceX96, tick) = IUniswapV3Pool(pool).slot0();
    }

    function findBestRate(IERC20 srcToken, IERC20 dstToken) external override returns (uint256 bestRate, address[] memory path, int24 bestSpacing) {
        bestRate = 0; // Initialize the best rate
        address[] memory bestPath = new address[](3); // Assume the path contains up to three addresses (src -> connector -> dst)

        // Iterate over all fees
        for (uint256 tickIndex = 0; tickIndex < tickSpacings.length; tickIndex++) {
            int24 tickSpacing = tickSpacings[tickIndex];

            (uint256 directRate, ) = _getRate(srcToken, dstToken, tickSpacing); // Calculate rate using the current fee
            // Update best rate and path if the direct rate is higher
            if (directRate > bestRate) {
                bestRate = directRate;
                bestPath[0] = address(srcToken);
                bestPath[1] = address(dstToken);
                bestSpacing = tickSpacing; // Record the best fee
            }

            // Case 1: Use all possible connectors for conversion
            for (uint256 i = 0; i < _connectors.length(); i++) {
                IERC20 connector = IERC20(_connectors.at(i));
                if (srcToken == connector || dstToken == connector) {
                    continue;
                }
                (uint256 rate0, ) = _getRate(srcToken, connector, tickSpacing); // Calculate rate using the current fee
                (uint256 rate1, ) = _getRate(connector, dstToken, tickSpacing); // Calculate rate using the current fee

                // Check if both rates are greater than zero
                if (rate0 > 0 && rate1 > 0) {
                    uint256 combinedRate = rate0 * rate1 / 1 ether; // Calculate the combined rate
                    // Update best rate and path if the combined rate is higher
                    if (combinedRate > bestRate) {
                        bestRate = combinedRate;
                        bestPath[0] = address(srcToken);
                        bestPath[1] = address(connector);
                        bestPath[2] = address(dstToken);
                        bestSpacing = tickSpacing; // Record the best fee
                    }
                }
            }
        }

        return (bestRate, bestPath, bestSpacing); // Return the best rate, path, and fee
    }
}
