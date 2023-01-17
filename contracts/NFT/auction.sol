// SPDX-License-Identifier: NONE

pragma solidity 0.8.1;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721Receiver.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/utils/ERC721Holder.sol";

interface IMarketplace {
    function setNftForSale(address _token, uint256 _tokenId, uint256 _maticPrice, uint256 _xvmcPrice) external;
    function bids(uint256,uint256) external view returns(address,address,uint256,bool);
    function nrOfBids(uint256 _saleId) external view returns (uint256);
    function acceptBid(uint256 _saleId, uint256 _bidId) external;
}

interface ILand {
    function xvmcRate() external view returns(uint256);
    function maticRate() external view returns(uint256);
}

interface IChainlink {
	function latestAnswer() external view returns (int256);
}

interface IXvmcOracle {
    function getPrice() external view returns(uint256);
}

interface IXVMC {
    function governor() external view returns(address);
}

/**
 * Auction contract
 * !!! Warning: !!! Copyrighted
 */
contract XVMCnftAuction is ERC721Holder {
    address public immutable marketplaceContract;
    address public immutable landContract;
    address public immutable priceOracle;
    address public immutable xvmc = 0x970ccEe657Dd831e9C37511Aa3eb5302C1Eb5EEe;
    address public immutable buyback = 0x0FECE73ab7c95258AF456661A16F10b615b51158;
    address public immutable chainlinkMATIC = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;

    uint256 public auctionEnd;

    mapping(uint256 => uint256) public highestBidMatic;
    mapping(uint256 => uint256) public highestBidXvmc; 
    mapping(uint256 => uint256) public highestBidId; 
    mapping(uint256 => uint256) public safeTime;  
    mapping(uint256 => uint256) public nrOfBids;

    constructor(
        address _marketplaceContract,
        address _NFTcontract,
        address _xvmcOracle
    ) {
        marketplaceContract = _marketplaceContract;
        landContract = _NFTcontract;
        priceOracle = _xvmcOracle;
        auctionEnd = block.timestamp + 86400 * 7; // 7 days

        IERC721(_NFTcontract).setApprovalForAll(_marketplaceContract, true);
    }

    function setNFTforAuction(uint256[] calldata tokenId) external {
        uint256 xvmcPrice = ILand(landContract).xvmcRate();
        uint256 maticPrice = ILand(landContract).maticRate();

        for(uint i=0; i < tokenId.length; i++) {
            uint256 maticActual = maticPrice * 100 * (200 - tokenId[i]) / 100;
            uint256 xvmcActual = xvmcPrice * 100 * (200 - tokenId[i]) / 100;
            IMarketplace(marketplaceContract).setNftForSale(landContract, tokenId[i], maticActual, xvmcActual);
        }
    }

    function acceptHighestBid(uint256 saleId, uint256 bidId) external {
        require(block.timestamp > auctionEnd, "auction is still on-going!");
        uint256 _bidLength = IMarketplace(marketplaceContract).nrOfBids(saleId);

        uint256 _maticPrice = uint256(IChainlink(chainlinkMATIC).latestAnswer()) * 1e10;
        uint256 _xvmcPrice = IXvmcOracle(priceOracle).getPrice();

        uint256 highestOffer;
        uint256 highestOfferId;
        for(uint i = 0; i < _bidLength; i++) {
            ( , address _token, uint256 _bidAmount, bool _valid) = IMarketplace(marketplaceContract).bids(saleId, bidId);
            if(_valid) {
                if(_token == xvmc) {
                    uint256 currentBid = _bidAmount * _xvmcPrice;
                    if(currentBid > highestOffer) {
                        highestOffer = currentBid;
                        highestOfferId = i;
                    }
                } else if(_token == address(1337)) {
                    uint256 currentBid = _bidAmount * _maticPrice;
                    if(currentBid > highestOffer) {
                        highestOffer = currentBid;
                        highestOfferId = i;
                    }
                }
            }
        }

        IMarketplace(marketplaceContract).acceptBid(saleId,highestOfferId);
    }

    //in case of a "spam-attack", where transaction could run out of gas before checking all bids
    //or in an unusual situation where there were too many bids
    function acceptHighestManualIntervention(uint256 saleId, uint256 bidId) external {
        require(block.timestamp > auctionEnd + 86400, "not yet mature");

        ( , address _token, uint256 _bidAmount, ) = IMarketplace(marketplaceContract).bids(saleId, bidId);

        require(_token == xvmc || _token == address(1337), "illegal token attempt");

        if(_token == xvmc) {
            require(_bidAmount == highestBidXvmc[bidId], "invalid");
        } else if(_token == address(1337)) {
            require(_bidAmount == highestBidMatic[bidId], "invalid");    
        }

        require(block.timestamp > safeTime[saleId] + 3600, "pending safe time");

        IMarketplace(marketplaceContract).acceptBid(saleId,bidId);
    }

    function getNrOfSaleBids(uint256 saleId) external {
        require(block.timestamp > auctionEnd, "auction is still on-going!");
        require(nrOfBids[saleId] == 0, "already recorded");

        nrOfBids[saleId] = IMarketplace(marketplaceContract).nrOfBids(saleId);
    }


    function reserveHighestBid(uint256 saleId, uint256 bidId) external {
        require(bidId < nrOfBids[saleId], "invalid bid");
        ( , address _token, uint256 _bidAmount, bool _valid) = IMarketplace(marketplaceContract).bids(saleId, bidId);
        require(_valid, "bid invalid");
        require(_token == xvmc || _token == address(1337), "illegal token attempt");

        uint256 _maticPrice = uint256(IChainlink(chainlinkMATIC).latestAnswer()) * 1e10;
        uint256 _xvmcPrice = IXvmcOracle(priceOracle).getPrice();

        if(_token == xvmc) {
            uint256 currentBid = _xvmcPrice * _bidAmount;

            if(!(currentBid > highestBidXvmc[bidId] && currentBid > highestBidMatic[bidId])) {
                ( , , , bool _valid2) = IMarketplace(marketplaceContract).bids(saleId, highestBidId[saleId]);
                require(!_valid2, "bid is still valid, but not highest offer"); //bid is invalid, can be replaced
            }

            highestBidXvmc[bidId] = _bidAmount;
            highestBidId[saleId] = bidId;
            safeTime[saleId] = block.timestamp;

        } else if(_token == address(1337)) {
            uint256 currentBid = _maticPrice * _bidAmount;

            if(!(currentBid > highestBidXvmc[bidId] && currentBid > highestBidMatic[bidId])) {
                ( , , , bool _valid2) = IMarketplace(marketplaceContract).bids(saleId, highestBidId[saleId]);
                require(!_valid2, "bid is still valid, but not highest offer"); //bid is invalid, can be replaced
            }

            highestBidMatic[bidId] = _bidAmount;
            highestBidId[saleId] = bidId;
            safeTime[saleId] = block.timestamp;
        }
    }

    function cashoutToBuyback() external {
        IERC20(xvmc).transfer(buyback, IERC20(xvmc).balanceOf(address(this)));
        payable(buyback).transfer(address(this).balance);
    }

    //backup
    function call(address _contract, bytes memory data) external {
        require(msg.sender == governor(), "decentralized voting only");
        _contract.call(data);
    }

    function governor() public view returns (address) {
		return IXVMC(xvmc).governor();
	}

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}
