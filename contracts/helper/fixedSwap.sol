// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

interface IToken {
	function governor() external view returns (address);
}
interface IGovernor {
	function treasuryWallet() external view returns (address);
}
interface IChainlink {
	function latestAnswer() external view returns (int256);
}

contract fixedSwapXVMC {
	address public immutable XVMCtoken;
	address public immutable wETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
	address public immutable usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

	uint256 public immutable rate; //amount of XVMC per 1 USDC

	address public chainlinkWETH = 0xF9680D99D6C9589e2a93a78A04A279e509205945;
	address public chainlinkMATIC = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;

	event Swap(address sender, address sendToken, uint256 depositAmount, uint256 withdrawAmount);
    
	constructor(address _xvmc, uint256 _rate) {
		XVMCtoken = _xvmc;
		rate = _rate;
	}

	
	function swapWETHforXVMC(uint256 amount) external {
		address _governor = IToken(XVMCtoken).governor();
		address _treasuryWallet = IGovernor(_governor).treasuryWallet();

		uint256 _toSend = getWETHinfo(amount);
		require(IERC20(wETH).transferFrom(msg.sender, _treasuryWallet, amount));
		IERC20(XVMCtoken).transfer(msg.sender, _toSend);

		emit Swap(msg.sender, wETH, amount, _toSend);
	}

	function swapMATICforXVMC(uint256 amount) payable public {
		require(msg.value == amount);

		address _governor = IToken(XVMCtoken).governor();
		address _treasuryWallet = IGovernor(_governor).treasuryWallet();

		payable(_treasuryWallet).transfer(amount);

		uint256 _toSend = getMaticInfo(amount);

		IERC20(XVMCtoken).transfer(msg.sender, _toSend);

		emit Swap(msg.sender, 0x0000000000000000000000000000000000001010, amount, _toSend);
	}

	function swapUSDCforXVMC(uint256 amount) external {
		address _governor = IToken(XVMCtoken).governor();
		address _treasuryWallet = IGovernor(_governor).treasuryWallet();

		uint256 _toSend = amount * 1e12 * rate;

		require(IERC20(usdc).transferFrom(msg.sender, _treasuryWallet, amount));
		IERC20(XVMCtoken).transfer(msg.sender, _toSend);

		emit Swap(msg.sender, usdc, amount, _toSend);
	}

	//governing contract can cancle the sale and withdraw tokens
	function withdrawXVMC(uint256 amount, address _token) external {
		address _governor = IToken(XVMCtoken).governor();
		require(msg.sender == _governor, "Governor only!");
		IERC20(_token).transfer(_governor, amount);
	}

	function getWETHinfo(uint256 _amount) public view returns (uint256) {
		uint256 wETHprice = uint256(IChainlink(chainlinkWETH).latestAnswer());

		return (_amount * wETHprice * rate / 1e8); //amount deposited * price of eth * rate(of XVMC per 1udc)
	}

	function getMaticInfo(uint256 _amount) public view returns (uint256) {
		uint256 maticPrice = uint256(IChainlink(chainlinkMATIC).latestAnswer());

		return (_amount * maticPrice * rate / 1e8); 
	}
	
}

