// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/utils/ERC721Holder.sol";

interface IToken {
    function governor() external view returns (address);
}

contract NFTtreasuryXVMC is Ownable, IERC721Receiver, ERC721Holder {
    address public immutable xvmc; //XVMC token address
	
	constructor(address _XVMC) {
		xvmc = _XVMC;
    }
    
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
	
	//safe transfer NFT (can be used for sending or claiming NFTs)
	function transferNFT(address token, address from, address to, uint256 tokenID) external onlyOwner returns (bool) {
        if(IERC721(token).getApproved(tokenID) == to) {
            IERC721(token).safeTransferFrom(from, to, tokenID);
            return true;
        } else {
            return false;
        }
    }
    
    function approveNFT(address claimer, address token, uint256 tokenID) external onlyOwner {
        IERC721(token).approve(claimer, tokenID);
    }

    function approveNFTall(address claimer, address token, bool approval) external onlyOwner {
        IERC721(token).setApprovalForAll(claimer, approval);
    }

	//Governor is the owner of masterchef(and masterchef owns the token)
	function changeGovernor() external {
		_transferOwnership(IToken(xvmc).governor());
    }
}
