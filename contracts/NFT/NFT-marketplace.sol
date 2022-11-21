// SPDX-License-Identifier: NONE

pragma solidity 0.8.1;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.0/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721Receiver.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/utils/ERC721Holder.sol";

interface IGovernor {
	function treasuryWallet() external view returns(address);
}

interface IXVMC {
	function governor() external view returns(address);
}


contract NFTmarketplace is ERC721Holder, ReentrancyGuard {
    struct NFTsale {
        address token;
        uint256 tokenId;
        uint256 maticPrice;
        uint256 xvmcPrice;
        address owner;
        bool isValid;
    }

    struct Offer {
        address bidder;
        address offeredToken;
        uint256 amount;
        bool isValid;
    }
    address public immutable xvmcToken; 

    NFTsale[] public nftOfferings;

    mapping(uint256 => Offer[]) public bids; //bids for certain saleId

    uint256 public provision = 100;
    uint256 public constant maxFee = 500; //max 5%

    constructor(address _xvmc) {
        xvmcToken = _xvmc;
    }

    event SetNftForSale(uint256 saleId, address token, uint256 tokenId, uint256 maticPrice, uint256 xvmcPrice, address indexed seller);
    event NftSold(uint256 offeringId, address indexed buyer, address forToken, uint256 provision);
    event UpdateSale(bool cancled, uint256 saleId, uint256 priceMatic, uint256 priceXvmc);

    event CreateBid(address indexed bidder, uint256 saleId, address offeredToken, uint256 amount);
    event ChangeBid(bool accept, uint256 saleId, uint256 bidId);

    receive() external payable {}
    fallback() external payable {}

    function setNftForSale(address _token, uint256 _tokenId, uint256 _maticPrice, uint256 _xvmcPrice) external {
        require (_maticPrice !=0 || _xvmcPrice !=0, "price must be non-null");
        IERC721(_token).safeTransferFrom(msg.sender, address(this), _tokenId);
        nftOfferings.push(
                NFTsale(_token, _tokenId, _maticPrice, _xvmcPrice, msg.sender, true)
            );

        emit SetNftForSale(nftOfferings.length-1, _token, _tokenId, _maticPrice, _xvmcPrice, msg.sender);
    }

    function swapNftMatic(uint256 _saleId) external payable nonReentrant {
        NFTsale storage sale = nftOfferings[_saleId];
        require(sale.isValid, "already sold");
        address treasury = getTreasury();
        uint256 amount;
        uint256 fee;
        amount = sale.maticPrice;
        require(sale.maticPrice != 0, "only swap for XVMC is allowed");
        require(msg.value == amount, "incorrect amount");
        fee = amount * provision / 10000;
        amount-=fee;
        payable(treasury).transfer(fee);
        payable(sale.owner).transfer(amount);
        
        sale.isValid = false;

        IERC721(sale.token).safeTransferFrom(address(this), msg.sender, sale.tokenId);

        emit NftSold(_saleId, msg.sender, address(1337), fee);
    }

    function swapNft(uint256 _saleId) external nonReentrant {
        NFTsale storage sale = nftOfferings[_saleId];
        require(sale.isValid, "already sold");
        address treasury = getTreasury();
        uint256 amount;
        uint256 fee;

        amount = sale.xvmcPrice;
        fee = amount * provision / 10000;
        amount-=fee;
        require(sale.xvmcPrice != 0, "only swap for MATIC is allowed");
        require(IERC20(xvmcToken).transferFrom(msg.sender, treasury, fee));
        require(IERC20(xvmcToken).transferFrom(msg.sender, sale.owner, amount));
        
        sale.isValid = false;

        IERC721(sale.token).safeTransferFrom(address(this), msg.sender, sale.tokenId);

        emit NftSold(_saleId, msg.sender, xvmcToken, fee);
    }

    function cancleSale(uint256 _saleId) external nonReentrant {
        NFTsale storage sale = nftOfferings[_saleId];
        require(sale.isValid, "already sold");
        require(sale.owner == msg.sender, "not owner");

        IERC721(sale.token).safeTransferFrom(address(this), msg.sender, sale.tokenId);

        sale.isValid = false;

        emit UpdateSale(true, _saleId, 0, 0);
    }

    function updateSale(uint256 _saleId, uint256 _maticPrice, uint256 _xvmcPrice) external nonReentrant {
        require (_maticPrice !=0 || _xvmcPrice !=0, "price must be non-null");
        NFTsale storage sale = nftOfferings[_saleId];
        require(sale.isValid, "already sold");
        require(sale.owner == msg.sender, "not owner");

        sale.maticPrice = _maticPrice;
        sale.xvmcPrice = _xvmcPrice;

        emit UpdateSale(false, _saleId, _maticPrice, _xvmcPrice);
    }

    function updateFee(uint256 _provision) external {
        require(_provision <= maxFee, "max 5%");
        require(msg.sender == getGovernor(), "only governor");
        provision = _provision;
    }

    function createBid(uint256 _saleId, address _offerToken, uint256 _amount) external payable nonReentrant {
        if(_offerToken != address(1337)) {
            require(IERC20(_offerToken).transferFrom(msg.sender, address(this), _amount), "transfer failed");
        } else {
            require(msg.value == _amount, "transfer failed");
        }
        
        bids[_saleId].push(
                Offer(msg.sender, _offerToken, _amount, true)
            );
        emit CreateBid(msg.sender, _saleId, _offerToken, _amount);
    }

    function acceptBid(uint256 _saleId, uint256 _bidId) external nonReentrant {
        Offer storage _bid = bids[_saleId][_bidId];
        NFTsale storage sale = nftOfferings[_saleId];
        require(msg.sender == sale.owner, "only seller can accept bid, obviously");
        require(sale.isValid, "already sold");
        require(_bid.isValid, "invalid");

        IERC721(sale.token).safeTransferFrom(address(this), _bid.bidder, sale.tokenId);

        uint256 fee = _bid.amount * provision / 10000;

        if(_bid.offeredToken != address(1337)) {
            require(IERC20(_bid.offeredToken).transfer(getTreasury(), fee), "transfer failed");
            require(IERC20(_bid.offeredToken).transfer(msg.sender, (_bid.amount-fee)), "transfer failed");
        } else {
            payable(getTreasury()).transfer(fee);
            payable(msg.sender).transfer(_bid.amount-fee);
        }
       
        
        sale.isValid = false;
        _bid.isValid = false;

        emit ChangeBid(true, _saleId, _bidId);
        emit NftSold(_saleId, msg.sender, _bid.offeredToken, fee);
    }

    function pullBid(uint256 _saleId, uint256 _bidId) external nonReentrant {
        Offer storage _bid = bids[_saleId][_bidId];
        require(msg.sender == _bid.bidder, "owner only");
        require(_bid.isValid, "invalid");

        if(_bid.offeredToken != address(1337)) {
            require(IERC20(_bid.offeredToken).transfer(msg.sender, _bid.amount), "transfer failed");
        } else {
            payable(msg.sender).transfer(_bid.amount);
        }
        _bid.isValid = false;

        emit ChangeBid(false, _saleId, _bidId);
    }

    function getTreasury() public view returns(address) {
        return IGovernor(getGovernor()).treasuryWallet();
    }

    function getGovernor() public view returns(address) {
        return IXVMC(xvmcToken).governor();
    }
}
