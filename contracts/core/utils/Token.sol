// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Token is ERC20, Ownable {
    uint public initialSupply = 10000000 ether;

    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
        Ownable()
    {
        _mint(msg.sender, initialSupply);
    }
}