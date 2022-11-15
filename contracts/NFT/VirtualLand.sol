// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.0/contracts/security/ReentrancyGuard.sol";

interface IChainlink {
	function latestAnswer() external view returns (int256);
}

interface IOracle {
	function getPrice() external view returns(uint256);
}

contract VirtualLand is ERC721URIStorage, ReentrancyGuard {
	address public immutable XVMC = 0x970ccEe657Dd831e9C37511Aa3eb5302C1Eb5EEe; //token address
	address public immutable buybackContract; // treasury 

    uint256 public tokenCount;

	uint256 public maticRate;
	uint256 public wethRate;
	uint256 public xvmcRate;

    address public immutable wETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
	address public immutable usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

	address public chainlinkWETH = 0xF9680D99D6C9589e2a93a78A04A279e509205945;
	address public chainlinkMATIC = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;
	address public xvmcOracle;
	
	uint256 public lastUpdate;
	uint256 public delayPeriod = 3600;
	
	event SetTokenURI(uint256 tokenID, string URI);
	event Mint(uint256 currency, address mintedTo, uint256[] mintedIds);

    constructor(address _buyBackContract, address _oracle, address _xvmcNftTreasury) ERC721("Mac&Cheese Virtual Land", "XVMC Land") {
		buybackContract = _buyBackContract;
		xvmcOracle = _oracle;
		_mint(_xvmcNftTreasury, 0);
		_mint(_xvmcNftTreasury, 1);
		_mint(_xvmcNftTreasury, 2);
		_mint(_xvmcNftTreasury, 3);
	}

    function mintNFTwithMATIC(uint256[] calldata landPlotIDs) external nonReentrant {
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
    	require(lastUpdate + delayPeriod < block.timestamp, "must wait delay period before updating");
		uint256 maticPrice = uint256(IChainlink(chainlinkMATIC).latestAnswer());
		uint256 wETHprice = uint256(IChainlink(chainlinkWETH).latestAnswer());

		maticRate = 1e27 / maticPrice; // 1e19 * 1e8 (to even out oracle)
		wethRate = 1e27 / wETHprice;
		xvmcRate = 1e19 / IOracle(xvmcOracle).getPrice();
		
		lastUpdate = block.timestamp;
    }
}
