# clmm-aggregator (CLMM) Project
This repository contains a sample of a concentrated liquidity market maker(CLMM) developed to show my skills as a Smart Contract developer with Solidity.
The architecture of the project is based on the UniswapV3 protocol and implements the constant product model. The project was developed using Foundry, Openzeppelin-contracts.<br />
The project can find the optimal path for exchange through the best route, thereby maximizing exchange benefits.

These are the addresses of the contracts deployed on the **Sepolia** test network:

**CLFactory**: [0x7C9B9ec2aAE220da6a806E79E138F91D44F42f64](https://sepolia.etherscan.io/address/0x7C9B9ec2aAE220da6a806E79E138F91D44F42f64#code)

**SwapRouter**: [0x2868070E8BE4125C768685CDdB06DC692F490788](https://sepolia.etherscan.io/address/0x2868070E8BE4125C768685CDdB06DC692F490788#code)

**Oracle**: [0x50f3e5710554B4C489b425d6c0910eac25d3B4E2](https://sepolia.etherscan.io/address/0x50f3e5710554B4C489b425d6c0910eac25d3B4E2#code)

## Smart Contracts ##
1.**SwapRouter**: The router is the contract designed to interact with the pool factory and the liquidity pools. <br />

2.**CLFactory**: The pool factory manage and creates different CLPools. <br />

3.**Oracle**: Find the optimal exchange path by comparing the exchange rates of different pools. <br />

## Installation and Deployment ##
To execute the project run the following commands:
```
forge build
```
Remeber that you need to modify .env file and configure smart contract addresses for the Sepolia Network. [Alchemy](https://www.alchemy.com/) and [Infura](https://www.infura.io/) are very popular service providers. To deploy the contracts to the Sepolia test network follow the next steps:

```
forge script script/DeployAdress.s.sol --rpc-url=$Sepolia-RPC-URL --broadcast --private-key $key
```

After this step you created a new pool and you also added liquidity.

If you want to run tests based on the existing deployment, you can enter the following command.
```aiignore
forge test --fork-url $Sepolia-RPC-URL
```

## Features ##
These are some of the most important features implemented:
* Create a concentrated liquidity pool.
* Add and remove liquidity.
* Implements the constant product model of UniswapV3.
* find the optimal exchange path.
* Testing

> [!NOTE]
> Please observe that these contracts are not ready for a production environment. It is necessary to add more functionality and testing.