// SPDX-License-Identifier: None

import "./libs/standard/IERC20.sol";
import "./libs/standard/Address.sol";
import "./libs/standard/SafeERC20.sol";

interface IToken {
	function swapOldForNew(uint256 _amount) external returns(bool);
}

interface IacPool {
    function hopDeposit(uint256 _amount, address _recipientAddress, uint256 previousLastDepositedTime, uint256 _mandatoryTime) external;
	function migrateAllStakes(address _staker) external;
}

contract XVMCmigrator {
    using SafeERC20 for IERC20;
	
	IERC20 public immutable oldToken = IERC20(0x6d0c966c8A09e354Df9C48b446A474CE3343D912);
	IERC20 public immutable token;
	
	address public immutable oldPool;
	address public immutable newPool;
	
	function massMigrate(address[] calldata _address) external {
		for(uint8 i=0; i < _address.length; i++) { //max 255
			IacPool(oldPool).migrateAllStakes(_address[i]);
		}
	}
	
   constructor(IERC20 _XVMC, address _oldPool, address _newPool) {
        token = _XVMC;
		oldToken.safeApprove(address(token), type(uint256).max); //to exchange(swap) old for new token
		oldPool = _oldPool;
		newPool = _newPool;
    }

	function hopDeposit(uint256 _amount, address _recipient, uint256 _lastDepositedTime, uint256 _mandatoryTimeToServe) external {
		require(msg.sender == oldPool);
		
		oldToken.safeTransferFrom(oldPool, address(this), _amount);
		
		require(token.swapOldForNew(_amount));
		
		IacPool(newPool).hopDeposit((_amount*1000), _recipient, _lastDepositedTime, _mandatoryTimeToServe);
	}
	
}
