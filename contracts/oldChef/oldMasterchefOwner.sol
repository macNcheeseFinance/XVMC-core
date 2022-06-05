// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.1;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


interface IMasterChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function pendingEgg(uint256 _pid, address _user) external view returns (uint256);
    function devaddr() external view returns (address);
    function owner() external view returns (address);
    function setFeeAddress(address _feeAddress) external;
    function dev(address _devaddr) external;
    function transferOwnership(address newOwner) external;
}
interface INewToken {
    function swapOldForNew(uint256 _amount) external returns (bool);
    function burn(uint256 amount) external;
    function governor() external view returns (address);
}
interface IDummyToken {
    function updateOwner() external;
}


/**
 * Collects rewards from old chef and burns them
 * The link to the old chef is needed due to the small 'accident' that occured
 * A pool that is not a valid lpToken has been added, which prevents
 * the massUpdatePools() in masterchef being called
 * Consequentially the emissions can not ever be updated
 * This contract receives all the rewards from old masterchef and burns them
 * Owner of the masterchef can mint infinite tokens and has enormous control
 * The "sneaky" dev that launched old masterchef added another function
 * (approve) which could be used to grant access to withdraw funds from the old masterchef contract
 * However we took control after launch and made sure it has never been used, feel free to check event logs
 */
contract XVMColdChefOwner {
    using SafeERC20 for IERC20;

	
    IERC20 public token = IERC20(0x6d0c966c8A09e354Df9C48b446A474CE3343D912); // XVMC token
	
	IERC20 public newToken; // updated XVMC
	
	IERC20 public dummyToken; //dummy token for earning rewards

    IMasterChef public immutable masterchef;
	
	address public admin;
	
	uint256 public burnDelay =  42690; //Delay before burn can be enforcedd
	
	uint256 public poolID = 58;
	
	bool public renounced; // if renounced, the old masterchef is sealed in and can only be burned forever(else governor of new token has the power to take control)


    /**
     * @notice Constructor
     * @param _token: XVMC token contract
     * @param _masterchef: MasterChef contract
     * @param _admin: address of the admin
     */
    constructor(
		IERC20 _newToken,
		IERC20 _dummyToken,
        IMasterChef _masterchef,
        address _admin
    ) {
		newToken = _newToken;
		dummyToken = _dummyToken;
        masterchef = _masterchef;
        admin = _admin;

        dummyToken.safeApprove(address(_masterchef), type(uint256).max); //to deposit&earn in old chef
		token.safeApprove(address(_newToken), type(uint256).max); //to exchange(swap) old for new token
    }
    
	
    /**
     * @notice Checks if the msg.sender is the admin
     */
    modifier adminOnly() {
        require(msg.sender == INewToken(address(newToken)).governor(), "admin: wut?");
        _;
    }
	
    modifier notRenounced() {
        require(!renounced, "Not possible. Contract has been renounced");
        _;
    }

	function harvestRewards() public {
		IMasterChef(masterchef).withdraw(poolID, 0); //harvests rewards
		INewToken(address(newToken)).swapOldForNew(token.balanceOf(address(this))); //swaps in new chef to get new token
	}

	//the tokens can only be burned(can not be withdrawn&used)
	//But ownership of masterchef can still be changed with new rules(where funds could be used)
	//so there is an option to "renounce ownership" and permanently seal the old masterchef into burn-only mode
	function burnTokens(uint256 _amount) public adminOnly {
		harvestRewards();
		
		if(_amount == 0) {
			INewToken(address(newToken)).burn(newToken.balanceOf(address(this)));
		} else {
			INewToken(address(newToken)).burn(_amount);
		}
	}
	
	
    /**
     * When contract is launched, dummyToken shall be deposited to start earning rewards
     */
    function startEarning(uint256 _amount) external adminOnly notRenounced {
		IMasterChef(masterchef).deposit(poolID, _amount);
    }
	
    /**
     * Dummy token can be withdrawn if ever needed(allows for flexibility)
     */
	function stopEarning(uint256  _withdrawAmount) external adminOnly notRenounced {
		IMasterChef(masterchef).withdraw(poolID, _withdrawAmount);
	}
	
    /**
     * Withdraws dummyToken
     */
    function withdrawDummy(uint256 _amount) external adminOnly notRenounced {	
        if(_amount == 0) { 
			dummyToken.safeTransfer(admin, dummyToken.balanceOf(address(this)));
		} else {
			dummyToken.safeTransfer(admin, _amount);
		}
    }
	
	// IMPORTANT NOTE: in the old chef, ONLY the respective owner can change the address
	// eg. fee address can change fee address, dev address can change dev address
	// in new masterchef onlyOwner can change the addresses
	//functions to transfer Masterchef owner, fee and dev address to new contract(if need be)
	function setChefFeeAddress(address _newAddress) external adminOnly notRenounced {
		IMasterChef(masterchef).setFeeAddress(_newAddress);
	}
	function setChefDevAddress(address _newAddress) external adminOnly notRenounced {
		IMasterChef(masterchef).dev(_newAddress);
	}
	function setChefOwnerAddress(address _newAddress) external adminOnly notRenounced {
		IMasterChef(masterchef).transferOwnership(_newAddress);
	}

    /**
     * @notice Calculates the total underlying tokens
     * @dev It includes tokens held by the contract and held in MasterChef
     */
    function balanceOf() public view returns (uint256) {
        uint256 amount = IMasterChef(masterchef).pendingEgg(poolID, address(this)); 
        return (amount + token.balanceOf(address(this)));
    }
	
    function pendingRewards() public view returns (uint256) {
        uint256 amount = IMasterChef(masterchef).pendingEgg(poolID, address(this)); 
        return amount;
    }
	
	
	function setBurnDelay(uint256 _newDelay) external adminOnly {
		burnDelay = _newDelay;
	}
	
	
	// effectively "renounces ownership", renders the contract immutable and the tokens
     //	minted from old chef can never again be accessed, only perpetually burned
	function renounceOwnership() external adminOnly notRenounced {
		IDummyToken(address(dummyToken)).updateOwner(); //makes sure the owner of dummy is updated to this address
		renounced = true;
	}
	
	function setPoolID(uint256 _id) external adminOnly notRenounced {
		poolID = _id;
	}
}
