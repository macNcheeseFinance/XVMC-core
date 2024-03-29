// SPDX-License-Identifier: NONE
pragma solidity 0.8.1;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.0/contracts/security/ReentrancyGuard.sol";

interface IChainlink {
	function latestAnswer() external view returns (int256);
}

interface IOracle {
	function getPrice() external view returns(uint256);
}

interface IXvmc {
	function governor() external view returns (address);
}

contract VirtualLand is ERC721URIStorage, ReentrancyGuard {
	string private _name;
    string private _symbol;
	
	address public immutable XVMC = 0x970ccEe657Dd831e9C37511Aa3eb5302C1Eb5EEe; //token address
	address public immutable buybackContract; // treasury 

    uint256 public tokenCount;

	uint256 public maticRate;
	uint256 public wethRate;
	uint256 public immutable xvmcRate; //set fixed rate at launch

    address public immutable wETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
	address public immutable usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

	address public chainlinkWETH = 0xF9680D99D6C9589e2a93a78A04A279e509205945;
	address public chainlinkMATIC = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;
	
	uint256 public lastUpdate;
	
	event SetTokenURI(uint256 tokenID, string URI);
	event Mint(uint256 currency, address mintedTo, uint256[] mintedIds);

    constructor(address _buyBackContract, uint256 _xvmcRate, address _xvmcNftTreasury, address _auctionContract) ERC721("Mac&Cheese Virtual Land", "XVMC Land") {
		_name = "Mac&Cheese Virtual Land";
		_symbol = "XVMC Land";
		buybackContract = _buyBackContract;
		xvmcRate = _xvmcRate;
		_mint(_xvmcNftTreasury, 0);
		_mint(_xvmcNftTreasury, 1);
		_mint(_xvmcNftTreasury, 2);
		_mint(_xvmcNftTreasury, 3);
		
		// mint first district to contract that auctions them on the market
		for(uint i=4; i < 180; i++) {
			_mint(_auctionContract, i);
		}
	}
	
	modifier decentralizedVoting {
    	require(msg.sender == IXvmc(XVMC).governor(), "Governor only, decentralized voting required");
    	_;
    }

    function mintNFTwithMATIC(uint256[] calldata landPlotIDs) payable external nonReentrant {
		require(tokenCount + landPlotIDs.length <= 10000, "10 000 land plot limit reached");
		payable(buybackContract).transfer(landPlotIDs.length * maticRate);
		tokenCount+= landPlotIDs.length;
        for(uint i=0; i < landPlotIDs.length; i++) {
			require(landPlotIDs[i] < 10000, "maximum 10 000 mints");
			_mint(msg.sender, landPlotIDs[i]);
        }
		emit Mint(0, msg.sender, landPlotIDs);
    }

	function mintNFTwithUSDC(uint256[] calldata landPlotIDs) external nonReentrant {
		require(tokenCount + landPlotIDs.length <= 10000, "10 000 land plot limit reached");
		require(IERC20(usdc).transferFrom(msg.sender, buybackContract, landPlotIDs.length * 1e7), "ERC20 transfer failed");
		tokenCount+= landPlotIDs.length;
        for(uint i=0; i < landPlotIDs.length; i++) {
			require(landPlotIDs[i] < 10000, "maximum 10 000 mints");
			_mint(msg.sender, landPlotIDs[i]);
        }
		emit Mint(1, msg.sender, landPlotIDs);
    }

	function mintNFTwithWETH(uint256[] calldata landPlotIDs) external nonReentrant {
		require(tokenCount + landPlotIDs.length <= 10000, "10 000 land plot limit reached");
		require(IERC20(wETH).transferFrom(msg.sender, buybackContract, landPlotIDs.length * wethRate), "ERC20 transfer failed");
		tokenCount+= landPlotIDs.length;
        for(uint i=0; i < landPlotIDs.length; i++) {
			require(landPlotIDs[i] < 10000, "maximum 10 000 mints");
			_mint(msg.sender, landPlotIDs[i]);
        }
		emit Mint(2, msg.sender, landPlotIDs);
    }

	function mintNFTwithXVMC(uint256[] calldata landPlotIDs) external nonReentrant {
		require(tokenCount + landPlotIDs.length <= 10000, "10 000 land plot limit reached");
		require(IERC20(XVMC).transferFrom(msg.sender, buybackContract, landPlotIDs.length * xvmcRate), "ERC20 transfer failed");
		tokenCount+= landPlotIDs.length;
        for(uint i=0; i < landPlotIDs.length; i++) {
			require(landPlotIDs[i] < 10000, "maximum 10 000 mints");
			_mint(msg.sender, landPlotIDs[i]);
        }
		emit Mint(3, msg.sender, landPlotIDs);
    }
	
	// users can set land outlook
	function setTokenURI(uint256 _tokenId, string memory _tokenURI) external {
		require(msg.sender == ownerOf(_tokenId), "you are not the token owner!");
		_setTokenURI(_tokenId, _tokenURI);
		emit SetTokenURI(_tokenId, _tokenURI);
	}

    function updateRates() external {
		uint256 maticPrice = uint256(IChainlink(chainlinkMATIC).latestAnswer());
		uint256 wETHprice = uint256(IChainlink(chainlinkWETH).latestAnswer());

		maticRate = 1e27 / maticPrice; // 1e19 * 1e8 (to even out oracle)
		wethRate = 1e27 / wETHprice;
		
		lastUpdate = block.timestamp;
    }
	
	//Standard ERC20 makes name and symbol immutable
	//We add potential to rebrand for full flexibility if stakers choose to do so through voting
	function rebrandName(string memory _newName) external decentralizedVoting {
		_name = _newName;
	}
	function rebrandSymbol(string memory _newSymbol) external decentralizedVoting {
        _symbol = _newSymbol;
	}
	
    /**
     * @dev Returns the name of the token.
     */
    function name() public override view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public override view returns (string memory) {
        return _symbol;
    }
}
