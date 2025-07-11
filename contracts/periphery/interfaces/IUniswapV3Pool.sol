// SPDX-License-Identifier: MIT

pragma solidity =0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniswapV3Pool {
    function slot0() external view returns (uint160 sqrtPriceX96, int24); // returns reduced because forks use different types of returned values that we do not use
    function ticks(int24 tick) external view returns (uint128, int128);  // returns reduced because forks use different types of returned values that we do not use
    function tickSpacing() external view returns (int24);
    function token0() external view returns (IERC20 token);
    function liquidity() external view returns (uint128);
}
