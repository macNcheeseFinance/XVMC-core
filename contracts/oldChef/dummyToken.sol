// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IMasterchef {
    function owner() external view returns (address);
}

contract XVMColdMasterchefRewards is ERC20, ERC20Burnable, Ownable {
	address public immutable oldMasterchef = 0x9BD741F077241b594EBdD745945B577d59C8768e;
	
    bool public allowOwnerTransfer = true;

    constructor() ERC20("Collecting Rewards", "Previous XVMC") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function updateOwner() external {
        require(allowOwnerTransfer, "disabled");

        _transferOwnership(IMasterchef(oldMasterchef).owner());
    }

    function enableDisableOwnershipTransfer(bool _setting) public onlyOwner {
        allowOwnerTransfer = _setting;
    }
}
