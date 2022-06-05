// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

interface IToken {
    function governor() external view returns (address);
}

contract XVMCtrackerCDP is ERC20, ERC20Burnable {
	address public immutable xvmc;

    constructor(string memory _forDuration, address _xvmc) ERC20("Dummy Token", _forDuration) {
		xvmc = _xvmc;
	}
    
    modifier onlyOwner() {
        require(msg.sender == IToken(xvmc).governor(), "only governor allowed");
        _;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
