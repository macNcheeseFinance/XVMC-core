// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IToken {
    function governor() external view returns (address);
}

contract XVMCtrackerCDP is ERC20, ERC20Burnable, Ownable {
	address public immutable XVMCtoken = 0x84F71F85202E84d27b42199a2cE8d65CeF1EA189;

    constructor(string memory _forDuration) ERC20("Dummy Token", _forDuration) {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

	/*
	* transfers ownership to Governor
	* XVMCtoken is owned by Masterchef
	* Masterchef is owned by Governor
	*/
    function updateOwnerToGovernor() external {
        _transferOwnership(IToken(XVMCtoken).governor());
    }

}
