// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";

import {CLPool} from "contracts/core/CLPool.sol";
import {CLFactory} from "contracts/core/CLFactory.sol";
import {NonfungibleTokenPositionDescriptor} from "contracts/periphery/NonfungibleTokenPositionDescriptor.sol";
import {NonfungiblePositionManager} from "contracts/periphery/NonfungiblePositionManager.sol";
import {CustomSwapFeeModule} from "contracts/core/fees/CustomSwapFeeModule.sol";
import {CustomUnstakedFeeModule} from "contracts/core/fees/CustomUnstakedFeeModule.sol";
import {MixedRouteQuoterV1} from "contracts/periphery/lens/MixedRouteQuoterV1.sol";
import {QuoterV2} from "contracts/periphery/lens/QuoterV2.sol";
import {SwapRouter} from "contracts/periphery/SwapRouter.sol";
import {Token} from "contracts/core/utils/Token.sol";
import {WETH9} from "../contracts/core/utils/WETH.sol";
import {UniswapV3LikeOracle} from "../contracts/periphery/UniswapV3LikeOracle.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DeployAddress is Script {
    using stdJson for string;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.rememberKey(deployPrivateKey);
    string public constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string public outputFilename = vm.envString("OUTPUT_FILENAME");
    address public poolFactoryOwner = deployerAddress;
    string public jsonConstants;
    uint256 constant INITIAL_TOKENS = 10000 ether;

    // deployed contracts
    CLPool public poolImplementation;
    CLFactory public poolFactory;
    NonfungibleTokenPositionDescriptor public nftDescriptor;
    NonfungiblePositionManager public nft;
    CustomSwapFeeModule public swapFeeModule;
    CustomUnstakedFeeModule public unstakedFeeModule;
    MixedRouteQuoterV1 public mixedQuoter;
    QuoterV2 public quoter;
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

        UniswapV3LikeOracle oracle = new UniswapV3LikeOracle(address(poolFactory), initCodeHash, tickSpacings, existingConnectors);

        swapRouter = new SwapRouter({_factory: address(poolFactory), _WETH9: address(weth), _oracleAddress: address(oracle)});

        for (uint256 i = 0; i < names.length; i++) {
            Token(tokenAddresses[i]).approve(address(swapRouter), INITIAL_TOKENS);
        }
        console.log("PoolImplementation Address     = \"%s\";", vm.toString(address(poolImplementation)));
        console.log("poolFactory Address            = \"%s\";", vm.toString(address(poolFactory)));
        console.log("swapRouter Address             = \"%s\";", vm.toString(address(swapRouter)));
        console.log("weth Address                   = \"%s\";", vm.toString(address(weth)));

        vm.stopBroadcast();
    }
}
