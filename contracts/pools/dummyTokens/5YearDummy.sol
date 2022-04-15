// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IToken {
    function governor() external view returns (address);
}

contract XVMCtrackerCDP is ERC20, ERC20Burnable, Ownable {
	address public immutable XVMCtoken = tokenaddress;
	
    bool public allowOwnerTransfer = true;

    constructor() ERC20("Time Deposit", "5 Year XVMC") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

	/*
	* transfers ownership to Governor
	* XVMCtoken is owned by Masterchef
	* Masterchef is owned by Governor
	*/
    function updateOwnerToGovernor() external {
        require(allowOwnerTransfer, "disabled");

        _transferOwnership(IToken(XVMCtoken).governor());
    }

    function enableDisableOwnershipTransfer(bool _setting) public onlyOwner {
        allowOwnerTransfer = _setting;
    }
}