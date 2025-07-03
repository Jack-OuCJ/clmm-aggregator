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

contract DeployCL is Script {
    using stdJson for string;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.rememberKey(deployPrivateKey);
    string public constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string public outputFilename = vm.envString("OUTPUT_FILENAME");
    string public jsonConstants;

    // loaded variables
    address public team;
    address public weth;
    address public voter;
    address public factoryRegistry;
    address public poolFactoryOwner;
    address public feeManager;
    address public notifyAdmin;
    address public factoryV2;
    string public nftName;
    string public nftSymbol;

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
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

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

        string memory root = vm.projectRoot();
        string memory basePath = concat(root, "/script/constants/");
        string memory path = concat(basePath, constantsFilename);

        vm.startBroadcast(deployerAddress);
        // deploy pool + factory
        poolImplementation = new CLPool();
        poolFactory = new CLFactory({_poolImplementation: address(poolImplementation)});

        poolFactory.setOwner(poolFactoryOwner);

        swapRouter = new SwapRouter({_factory: address(poolFactory), _WETH9: weth, _oracleAddress: address(0)});
        vm.stopBroadcast();

        // write to file
        path = concat(basePath, "output/DeployCL-");
        path = concat(path, outputFilename);
        vm.writeJson(vm.serializeAddress("", "PoolImplementation", address(poolImplementation)), path);
        vm.writeJson(vm.serializeAddress("", "poolFactory", address(poolFactory)), path);
        vm.writeJson(vm.serializeAddress("", "swapRouter", address(swapRouter)), path);

        for (uint256 i = 0; i < names.length; i++) {
            Token token = new Token(names[i], symbols[i]);
            tokenAddresses[i] = address(token);
            vm.writeJson(vm.serializeAddress("", names[i], address(tokenAddresses[i])), path);
        }
    }

    function concat(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }
}
