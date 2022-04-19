// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IToken {
    function governor() external view returns (address);
}

contract XVMCtrackerCDP is ERC20, ERC20Burnable, Ownable {
	address public immutable XVMCtoken;

    constructor(address _XVMCtoken, string memory _forDuration) ERC20("Time Deposit", _forDuration) {
        XVMCtoken = _XVMCtoken;
    }

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
