// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

interface IToken {
    function governor() external view returns (address);
}

contract XVMCtrackerCDP is ERC20, ERC20Burnable {
	address public immutable XVMCtoken = ;

    constructor(string memory _forDuration) ERC20("Dummy Token", _forDuration) {}
    
    modifier onlyOwner() {
        require(msg.sender == IToken(XVMCtoken).governor(), "only governor allowed");
        _;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
