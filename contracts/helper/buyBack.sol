// SPDX-License-Identifier: NONE
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";

interface IXVMC {
	function governor() external view returns (address);
}

interface IGovernor {
	function treasuryWallet() external view returns (address);
}

contract BuybackXVMC {
    address internal constant UNISWAP_ROUTER_ADDRESS = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    address internal constant XVMC = 0x970ccEe657Dd831e9C37511Aa3eb5302C1Eb5EEe;

    IUniswapV2Router02 public uniswapRouter;

    address public immutable wETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
	address public immutable usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    constructor() {
        uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
        IERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619).approve(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff, type(uint256).max); // infinite allowance for wETH to quickswap router
        IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174).approve(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff, type(uint256).max); // infinite allowance for USDC to quickswap router
    }

    function buybackMATIC() external {
        uint deadline = block.timestamp + 15; 
        uint[] memory _minOutT = getEstimatedXVMCforETH(address(this).balance);
        uint _minOut = _minOutT[_minOutT.length-1] * 99 / 100;
        uniswapRouter.swapETHForExactTokens{ value: address(this).balance }(_minOut, getMATICpath(), address(this), deadline);
    }

    function buybackWETH() external {
        uint deadline = block.timestamp + 15; 
        uint[] memory _minOutT = getEstimatedXVMCforWETH(address(this).balance);
        uint _minOut = _minOutT[_minOutT.length-1] * 99 / 100;
        uniswapRouter.swapETHForExactTokens(_minOut, getWETHpath(), address(this), deadline);
    }

    function buybackUSDC() external {
        uint deadline = block.timestamp + 15; 
        uint[] memory _minOutT = getEstimatedXVMCforUSDC(address(this).balance);
        uint _minOut = _minOutT[_minOutT.length-1] * 99 / 100;
        uniswapRouter.swapETHForExactTokens(_minOut, getUSDCpath(), address(this), deadline);
    }


    function sendXVMCtoTreasury() external {
        require(IERC20(XVMC).transfer(treasury(), IERC20(XVMC).balanceOf(address(this))));
    }

    function withdraw() external {
        require(msg.sender == governor(), "only thru decentralized Governance");
        payable(treasury()).transfer(address(this).balance);
        IERC20(XVMC).transfer(treasury(), IERC20(XVMC).balanceOf(address(this)));
        IERC20(usdc).transfer(treasury(), IERC20(usdc).balanceOf(address(this)));
        IERC20(wETH).transfer(treasury(), IERC20(wETH).balanceOf(address(this)));
    }

    //with gets amount in you provide how much you want out
    function getEstimatedXVMCforETH(uint _eth) public view returns (uint[] memory) {
        return uniswapRouter.getAmountsOut(_eth, getMATICpath()); //NOTICE: ETH is matic MATIC
    }

    function getEstimatedXVMCforWETH(uint _weth) public view returns (uint[] memory) {
        return uniswapRouter.getAmountsOut(_weth, getWETHpath());
    }

    function getEstimatedXVMCforUSDC(uint _usdc) public view returns (uint[] memory) {
        return uniswapRouter.getAmountsOut(_usdc, getUSDCpath());
    }

    function getMATICpath() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = XVMC;

        return path;
    }

    function getWETHpath() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = XVMC;

        return path;
    }

    function getUSDCpath() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = usdc;
        path[1] = XVMC;

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
