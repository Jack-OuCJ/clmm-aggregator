// SPDX-License-Identifier: MIT

pragma solidity =0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOracle {
    event ConnectorShouldBeNone();
    event PoolNotFound();
    event PoolWithConnectorNotFound();

    function getRate(IERC20 srcToken, IERC20 dstToken, IERC20 connector, uint256 thresholdFilter) external view returns (uint256 rate, uint256 weight);
    function findBestRate(IERC20 srcToken, IERC20 dstToken) external view returns (uint256 bestRate, address[] memory path, int24 bestSpacing);
}
