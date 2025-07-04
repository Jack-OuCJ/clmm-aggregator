// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";

import {CLPool} from "contracts/core/CLPool.sol";
import {CLFactory} from "contracts/core/CLFactory.sol";
import {SwapRouter} from "contracts/periphery/SwapRouter.sol";
import {Token} from "contracts/core/utils/Token.sol";
import {WETH9} from "../contracts/core/utils/WETH.sol";
import {UniswapV3LikeOracle} from "../contracts/periphery/UniswapV3LikeOracle.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DeployAddress is Script {
    using stdJson for string;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.rememberKey(deployPrivateKey);
    address public poolFactoryOwner = deployerAddress;
    uint256 constant INITIAL_TOKENS = 10000 ether;

    // deployed contracts
    CLPool public poolImplementation;
    CLFactory public poolFactory;
    SwapRouter public swapRouter;

    function run() public {
        vm.startBroadcast(deployerAddress);

        string[] memory names = new string[](7);
        string[] memory symbols = new string[](7);
        address[] memory tokenAddresses = new address[](7);

        names[0] = "Token A";
        symbols[0] = "A";
        names[1] = "Token B";
        symbols[1] = "B";
        names[2] = "Token C";
        symbols[2] = "C";
        names[3] = "Token D";
        symbols[3] = "D";
        names[4] = "Token E";
        symbols[4] = "E";
        names[5] = "Token F";
        symbols[5] = "F";
        names[6] = "Token G";
        symbols[6] = "G";

        WETH9 weth = new WETH9();

        // deploy pool + factory
        poolImplementation = new CLPool();
        poolFactory = new CLFactory({_poolImplementation: address(poolImplementation)});
        poolFactory.setOwner(poolFactoryOwner);

        int24[] memory tickSpacings = new int24[](3);
        tickSpacings[0] = 10;
        tickSpacings[1] = 60;
        tickSpacings[2] = 200;

        IERC20[] memory existingConnectors = new IERC20[](7);
        for (uint256 i = 0; i < names.length; i++) {
            Token token = new Token(names[i], symbols[i]);

            tokenAddresses[i] = address(token);
            existingConnectors[i] = IERC20(address(token));
            console.log("%s Address                = \"%s\";", names[i], vm.toString(tokenAddresses[i]));
        }

        bytes memory bytecode_cl = type(CLPool).creationCode;
        bytes32 initCodeHash = keccak256(bytecode_cl);
        UniswapV3LikeOracle oracle = new UniswapV3LikeOracle(address(poolFactory),
            initCodeHash,
            tickSpacings,
            existingConnectors);
        swapRouter = new SwapRouter({_factory: address(poolFactory), _WETH9: address(weth), _oracleAddress: address(oracle)});

        for (uint256 i = 0; i < names.length; i++) {
            Token(tokenAddresses[i]).approve(address(swapRouter), INITIAL_TOKENS);
        }
        console.log("PoolImplementation Address     = \"%s\";", vm.toString(address(poolImplementation)));
        console.log("poolFactory Address            = \"%s\";", vm.toString(address(poolFactory)));
        console.log("swapRouter Address             = \"%s\";", vm.toString(address(swapRouter)));
        console.log("Oracle Address             = \"%s\";", vm.toString(address(oracle)));
        console.log("weth Address                   = \"%s\";", vm.toString(address(weth)));

        // A - B pool
        createPools(tokenAddresses[0], tokenAddresses[1], tickSpacings[0], 2 ** 95);
        // B - C pool
        createPools(tokenAddresses[1], tokenAddresses[2], tickSpacings[0], 2 ** 96);
        // A - C pool
        createPools(tokenAddresses[0], tokenAddresses[2], tickSpacings[0], 2 ** 96);

        uint length = poolFactory.allPoolsLength();
        console.log("length pool:", length);
        vm.stopBroadcast();
    }

    function createPools(address tokenA, address tokenB, int24 tickSpacing, uint160 price) internal {
        address newPool;
        newPool = poolFactory.createPool(tokenA, tokenB, tickSpacing, price);
        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            bool unlocked
        ) = CLPool(newPool).slot0();
        console.log("Created pool:", newPool);
        console.log("sqrtPriceX96:", uint256(sqrtPriceX96));
        console.log("tick:", tick);
        console.log("observationIndex:", uint256(observationIndex));
        console.log("observationCardinality:", uint256(observationCardinality));
        console.log("observationCardinalityNext:", uint256(observationCardinalityNext));
        console.log("unlocked:", unlocked);
    }
}
