// SPDX-License-Identifier: NONE
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";

interface IXVMC {
	function governor() external view returns (address);
	function burn(uint256 amount) external;
}

interface IGovernor {
	function treasuryWallet() external view returns (address);
}

contract BuybackXVMC {
    address public constant UNISWAP_ROUTER_ADDRESS = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    address public constant XVMC = 0x970ccEe657Dd831e9C37511Aa3eb5302C1Eb5EEe;

    IUniswapV2Router02 public uniswapRouter;

    address public immutable wETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
	address public immutable usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
	
	address public canPause;
	
	bool public toBurn = true;
	
	bool public paused = false;

    constructor() {
		canPause = msg.sender;
        uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
        IERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619).approve(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff, type(uint256).max); // infinite allowance for wETH to quickswap router
        IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174).approve(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff, type(uint256).max); // infinite allowance for USDC to quickswap router
    }

    function buybackMATIC() public {
    	require(msg.sender == tx.origin);
		require(!paused, "Buy-Backs are paused");
        uint deadline = block.timestamp + 15; 
        uint[] memory _minOutT = getEstimatedXVMCforETH();
        uint _minOut = _minOutT[_minOutT.length-1] * 99 / 100;
        uniswapRouter.swapETHForExactTokens{ value: address(this).balance }(_minOut, getMATICpath(), address(this), deadline);
    }

    function buybackWETH() public {
    	require(msg.sender == tx.origin);
		require(!paused, "Buy-Backs are paused");
        uint deadline = block.timestamp + 15; 
        uint[] memory _minOutT = getEstimatedXVMCforWETH();
        uint _minOut = _minOutT[_minOutT.length-1] * 99 / 100;
        uniswapRouter.swapTokensForExactTokens(_minOut, IERC20(wETH).balanceOf(address(this)), getWETHpath(), address(this), deadline);
    }

    function buybackUSDC() public {
    	require(msg.sender == tx.origin);
		require(!paused, "Buy-Backs are paused");
        uint deadline = block.timestamp + 15; 
        uint[] memory _minOutT = getEstimatedXVMCforUSDC();
        uint _minOut = _minOutT[_minOutT.length-1] * 99 / 100;
        uniswapRouter.swapTokensForExactTokens(_minOut, IERC20(usdc).balanceOf(address(this)), getUSDCpath(), address(this), deadline);
    }
	
	function buybackAndBurn(bool _matic, bool _weth, bool _usdc) external {
		if(_matic) {
			buybackMATIC();
		}
		if(_weth) {
			buybackWETH();
		}
		if(_usdc) {
			buybackUSDC();
		}
		burnTokens();
	}
	
    function burnTokens() public {
		if(toBurn) {
			IXVMC(XVMC).burn(IERC20(XVMC).balanceOf(address(this)));
		} else {
        	require(IERC20(XVMC).transfer(treasury(), IERC20(XVMC).balanceOf(address(this))));
		}
    }

    function withdraw() external {
        require(msg.sender == governor(), "only thru decentralized Governance");
        payable(treasury()).transfer(address(this).balance);
        IERC20(XVMC).transfer(treasury(), IERC20(XVMC).balanceOf(address(this)));
        IERC20(usdc).transfer(treasury(), IERC20(usdc).balanceOf(address(this)));
        IERC20(wETH).transfer(treasury(), IERC20(wETH).balanceOf(address(this)));
    }
	
	function switchBurn(bool _option) external {
		require(msg.sender == governor(), "only thru decentralized Governance");
		toBurn = _option;
	}
	
	function pauseBuyback(bool _setting) external {
		require(msg.sender == canPause, "not allowed");
		paused = _setting;
	}

    //with gets amount in you provide how much you want out
    function getEstimatedXVMCforETH() public view returns (uint[] memory) {
        return uniswapRouter.getAmountsOut(address(this).balance, getMATICpath()); //NOTICE: ETH is matic MATIC
    }

    function getEstimatedXVMCforWETH() public view returns (uint[] memory) {
        return uniswapRouter.getAmountsOut(IERC20(wETH).balanceOf(address(this)), getWETHpath());
    }

    function getEstimatedXVMCforUSDC() public view returns (uint[] memory) {
        return uniswapRouter.getAmountsOut(IERC20(usdc).balanceOf(address(this)), getUSDCpath());
    }

    function getMATICpath() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = XVMC;

        return path;
    }

    function getWETHpath() private view returns (address[] memory) {
        address[] memory path = new address[](3);
        path[0] = wETH; //wETH is wrapped Ethereum on Polygon
        path[1] = uniswapRouter.WETH(); // uni.WETH == wrapped MATIC 
        path[2] = XVMC;

        return path;
    }

    function getUSDCpath() private view returns (address[] memory) {
        address[] memory path = new address[](3);
        path[0] = usdc;
        path[1] = uniswapRouter.WETH();
        path[2] = XVMC;

        return path;
    }

	function governor() public view returns (address) {
		return IXVMC(XVMC).governor();
	}

  	function treasury() public view returns (address) {
		return IGovernor(governor()).treasuryWallet();
	}

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}
