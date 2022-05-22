// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

interface IMasterchef {
	function owner() external view returns (address);
}
interface IGovernor {
	function treasuryWallet() external view returns (address);
}

contract XVMC is ERC20, ERC20Burnable, Ownable {
	string private _name;
    string private _symbol;
	
	IERC20 public oldToken = IERC20(0x6d0c966c8A09e354Df9C48b446A474CE3343D912);
	bool public allowTrustedContracts = true;
	
    //trusted contracts can transfer and burn without allowance
	//only governor can set trusted contracts and governor is decentralized(you are the governor)
	mapping(address => bool) public trustedContract;
	
	//additionally, users can disable the feature and revert to mandatory allowance(as per ERC20 standard)
	mapping(address => bool) public requireAllowance;
	
	//easier to verify(without event logs)
	uint256 public trustedContractCount; 
    
	constructor() ERC20("Mac&Cheese", "XVMC") {
		_name = string("Mac&Cheese");
		_symbol = string("XVMC");
	}
	
    modifier decentralizedVoting {
    	require(msg.sender == governor(), "Governor only, decentralized voting required");
    	_;
    }
	
	event TrustedContract(address contractAddress, bool setting);
	event RequireAllowance(address wallet, bool setting);

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
	
	//enables swap from old token into new
	function swapOldForNew(uint256 amount) public returns (bool) {
		require(oldToken.transferFrom(msg.sender, address(this), amount));
		_mint(msg.sender, (amount * 1000));
		return true;
	}
	
	//swap new token for old one
	function swapNewForOld(uint256 amount) public returns (bool) {
		_burn(msg.sender, amount);
		require(oldToken.transfer(msg.sender, (amount / 1000)));
		return true;
	}
	
	/*
	* allows transfer without allowance for trusted contracts
	* trusted contracts can only be set through governor and governor is decentralized
	* trusted contract shall always require the signature of the owner(from address shall only ever be msg.sender)
	* governor also owns Masterchef which can set emissions and create new pools(mint new tokens)
	* Assuming governor is decentralized and secure, it improves user experience without compromising on security
	* If wallet sets mandatory allowance required, standard ERC20 transferFrom is used for the transfer
	*/
	function transferXVMC(address from, address to, uint256 amount) public returns (bool) {
		address spender = _msgSender();
		if(!requireAllowance[from] && trustedContract[spender]) {
			_transfer(from, to, amount);
		} else {
        	_spendAllowance(from, spender, amount);
        	_transfer(from, to, amount);
		}
		return true;
	}
	
	//leaving option for burning(upon deposit) if chosen instead of transferring
    function burnXVMC(address account, uint256 amount) public returns (bool) {
        address spender = _msgSender();
		if(!requireAllowance[account] && trustedContract[spender]) {
			_burn(account, amount);
		} else {
			_spendAllowance(account, spender, amount);
        	_burn(account, amount);
		}
		return true;
    }
	
	//only owner can set trusted Contracts
	function setTrustedContract(address _contractAddress, bool _setting) external decentralizedVoting {
		require(allowTrustedContracts, "Trusted contracts have been renounced");

		if(trustedContract[_contractAddress] != _setting) { //prevents messing up the count. Using if to avoid revert
			trustedContract[_contractAddress] = _setting;
			_setting ? trustedContractCount++ : trustedContractCount--;
			emit TrustedContract(_contractAddress, _setting);
		}
	}
	
	//option to globally disable trusted contracts and revert to the ERC20 standard
	//first set all current trustedContract settings to false, then call this function to renounce
	function renounceTrustedContracts(bool _setting) external decentralizedVoting {
		allowTrustedContracts = _setting;
	}
	
	//Option for individual addresses to revert to the ERC20 standard and require allowance for transferFrom(for exchanges)
	function requireAllowanceForTransfer(bool _setting) external {
		requireAllowance[msg.sender] = _setting;
		
		emit RequireAllowance(msg.sender, _setting);
	}
	
	//Standard ERC20 makes name and symbol immutable
	//We add potential to rebrand for full flexibility if stakers choose to do so through voting
	function rebrandName(string memory _newName) external decentralizedVoting {
		_name = _newName;
	}
	function rebrandSymbol(string memory _newSymbol) external decentralizedVoting {
        _symbol = _newSymbol;
	}
	
	//If tokens are accidentally sent to the contract. Could be returned to rightful owners at the mercy of XVMC governance
	function transferStuckTokens(address _token) external {
		require(msg.sender == tx.origin);
		require(_token != address(oldToken), "not allowed");
		address treasuryWallet = IGovernor(governor()).treasuryWallet();
		uint256 tokenAmount = IERC20(_token).balanceOf(address(this));
		
		IERC20(_token).transfer(treasuryWallet, tokenAmount);
	}
	
	// Governor is a smart contract that allows the control of the entire system in a decentralized manner
	//XVMC token is owned by masterchef and masterchef is owned by Governor
	function governor() public view returns (address) {
		return IMasterchef(owner()).owner();
	}
	
	function actualSupply() public view returns (uint256) {
		uint256 _actualSupply = totalSupply() + 1000 * (oldToken.totalSupply() - oldToken.balanceOf(address(this)));
		return _actualSupply;
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

