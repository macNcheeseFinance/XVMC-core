// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

interface IMasterchef {
    function owner() external view returns (address);
}

interface IToken {
	function governor() external view returns (address);
}

contract XVMColdMasterchefRewards is ERC20, ERC20Burnable {
	address public immutable oldMasterchef = 0x9BD741F077241b594EBdD745945B577d59C8768e;

    constructor() ERC20("Collecting Rewards", "Previous XVMC") {}
	
    modifier onlyOwner() {
        require(msg.sender == IToken(xvmc).governor(), "admin: wut?");
        _;
    }
	
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
