// SPDX-License-Identifier: NONE

pragma solidity 0.8.1;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.0/contracts/security/ReentrancyGuard.sol";


interface IacPool {
    function setCallFee(uint256 _callFee) external;
    function totalShares() external returns (uint256);
    function totalVotesFor(uint256 proposalID) external returns (uint256);
    function setAdmin(address _admin, address _treasury) external;
    function setTreasury(address _treasury) external;
	function addAndExtendStake(address _recipientAddr, uint256 _amount, uint256 _stakeID, uint256 _lockUpTokensInSeconds) external;
    function giftDeposit(uint256 _amount, address _toAddress, uint256 _minToServeInSecs) external;
    function harvest() external;
	function calculateHarvestXVMCRewards() external view returns (uint256);
}

interface IMasterChef {
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) external;
    function updateEmissionRate(uint256 _gajPerBlock) external;
    function setFeeAddress(address _feeAddress) external;
    function dev(address _devaddr) external;
    function transferOwnership(address newOwner) external;
    function XVMCPerBlock() external returns (uint256);
    function totalAllocPoint() external returns (uint256);
    function updatePool(uint256 _pid) external;
    function owner() external returns (address);
	function setGovernorFee(uint256 _amount) external;
    function pendingEgg(uint256 _pid, address _user) external view returns (uint256);
    function withdraw(uint256 _pid, uint256 _amount) external;
    function deposit(uint256 _pid, uint256 _amount) external;
}

interface IGovernor {
    function treasuryWallet() external view returns (address);
}


/**
 * MAITC vault
 * !!! Warning: !!! No license (copyrighted!)
 */
contract maticVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
		uint256 debt;
		uint256 feesPaid;
		address referredBy;
		uint256 lastAction;
    }

    struct PoolPayout {
        uint256 amount;
        uint256 minServe;
    }
	
	uint256 public constant maxFee = 250; // max 2.5%
	uint256 public constant maxFundingFee = 250; // max 0.025% per hour
	
    IERC20 public immutable token; // XVMC token
    
    IERC20 public immutable dummyToken; 

    IMasterChef public masterchef;  

    mapping(address => UserInfo[]) public userInfo;
    mapping(address => PoolPayout) public poolPayout; //determines the percentage received depending on withdrawal option
 
	uint256 public poolID = 11; 
	uint256 public accDtxPerShare;
    address public admin; //admin = governing contract!
    address public treasury = 0xA2e4728c89D6dCFc93dF4b2b438E49da823Fe181; // buyback & burn contract

    uint256 public defaultDirectPayout = 500; //5% if withdrawn into wallet
	
	uint256 public depositFee = 10; // 0.01% deposit fee (in case someone tried to cheat
	uint256 public fundingRate = 25;// 0.025% per Hour (divided by 1M)
	
	
	uint256 public refShare1 = 5000; // 50% ; initial deposit 
	uint256 public refShare2 = 4000; // 40% ; recurring fee
	

    event Deposit(address indexed sender, uint256 amount, uint256 debt, uint256 depositFee, address referral);
    event Withdraw(address indexed sender, uint256 stakeID, uint256 harvestAmount, uint256 penalty);
    event UserSettingUpdate(address indexed user, address poolAddress, uint256 threshold, uint256 feeToPay);

    event Harvest(address indexed harvester, address indexed benficiary, uint256 stakeID, address harvestInto, uint256 harvestAmount, uint256 penalty, uint256 callFee); //harvestAmount contains the callFee
    event SelfHarvest(address indexed user, address harvestInto, uint256 harvestAmount, uint256 penalty);
	
	event CollectedFee(address ref, uint256 amount);

    /**
     * @notice Constructor
     * @param _token: DTX token contract
     * @param _dummyToken: Dummy token contract
     * @param _masterchef: MasterChef contract
     * @param _admin: address of the admin
     * @param _treasury: address of the treasury (collects fees)
     */
    constructor(
        IERC20 _token,
        IERC20 _dummyToken,
        IMasterChef _masterchef,
        address _admin,
        address _treasury
    ) {
        token = _token;
        dummyToken = _dummyToken;
        masterchef = _masterchef;
        admin = _admin;
        treasury = _treasury;

        IERC20(_dummyToken).safeApprove(address(_masterchef), type(uint256).max);
		poolPayout[0xfFB71361dD8Fc3ef0831871Ec8dd51B413ed093C].amount = 750;
        poolPayout[0xfFB71361dD8Fc3ef0831871Ec8dd51B413ed093C].minServe = 864000;

        poolPayout[0x9a9AEF66624C3fa77DaACcA9B51DE307FA09bd50].amount = 1500;
        poolPayout[0x9a9AEF66624C3fa77DaACcA9B51DE307FA09bd50].minServe = 2592000;

        poolPayout[0x1F8a5D98f1e2F10e93331D27CF22eD7985EF6a12].amount = 2500;
        poolPayout[0x1F8a5D98f1e2F10e93331D27CF22eD7985EF6a12].minServe = 5184000;

        poolPayout[0x30019481FC501aFa449781ac671103Feb0d6363C].amount = 5000;
        poolPayout[0x30019481FC501aFa449781ac671103Feb0d6363C].minServe = 8640000;

        poolPayout[0x8c96105ea574727e94d9C199c632128f1cA584cF].amount = 7000;
        poolPayout[0x8c96105ea574727e94d9C199c632128f1cA584cF].minServe = 20736000;

        poolPayout[0x605c5AA14BdBf0d50a99836e7909C631cf3C8d46].amount = 10000;
        poolPayout[0x605c5AA14BdBf0d50a99836e7909C631cf3C8d46].minServe = 31536000; 
    }
    
    /**
     * @notice Checks if the msg.sender is the admin
     */
    modifier adminOnly() {
        require(msg.sender == admin, "admin: wut?");
        _;
    }
	
    receive() external payable {}
    fallback() external payable {}

	
    /**
     * Creates a NEW stake
     * _poolInto is the pool to harvest into(time deposit option)
	 * threshold is the amount to allow another user to harvest 
	 * fee is the amount paid to harvester
     */
    function deposit(uint256 _amount, address referral) external payable nonReentrant {
        require(msg.value == _amount && _amount > 0, "invalid amount");
        harvest();
		
		uint256 _depositFee = _amount * depositFee / 10000;
		_amount = _amount - _depositFee;

        uint256 commission = 0;
		
		if(referral != msg.sender && _depositFee > 0) {
			commission = _depositFee * refShare1 / 10000;
			payable(referral).transfer(commission);
		}
		
		payable(treasury).transfer(_depositFee - commission);
		
		uint256 _debt = _amount * accDtxPerShare / 1e12;

        userInfo[msg.sender].push(
                UserInfo(_amount, _debt, _depositFee, referral, block.timestamp)
            );

        emit Deposit(msg.sender, _amount, _debt, _depositFee, referral);
    }

    /**
     * Harvests into pool
     */
    function harvest() public {
		uint256 _pending = IMasterChef(masterchef).pendingEgg(poolID, address(this));
        IMasterChef(masterchef).withdraw(poolID, 0);
		accDtxPerShare+= _pending * 1e12  / address(this).balance;
    }


    /**
     * Withdraws all tokens
     */
    function withdraw(uint256 _stakeID, address _harvestInto) public nonReentrant {
        harvest();
        require(_stakeID < userInfo[msg.sender].length, "invalid stake ID");
        UserInfo storage user = userInfo[msg.sender][_stakeID];
        
        payFee(user);

		uint256 userTokens = user.amount; 

		uint256 currentAmount = userTokens * accDtxPerShare / 1e12 - user.debt;
		
		_removeStake(msg.sender, _stakeID);

        uint256 _toWithdraw;      

        if(_harvestInto == msg.sender) { 
            _toWithdraw = currentAmount * defaultDirectPayout / 10000;
            currentAmount = currentAmount - _toWithdraw;
            token.safeTransfer(msg.sender, _toWithdraw);
         } else {
            require(poolPayout[_harvestInto].amount != 0, "incorrect pool!");
            _toWithdraw = currentAmount * poolPayout[_harvestInto].amount / 10000;
            currentAmount = currentAmount - _toWithdraw;
            IacPool(_harvestInto).giftDeposit(_toWithdraw, msg.sender, poolPayout[_harvestInto].minServe);
        }
        token.safeTransfer(treasury, currentAmount); //penalty goes to governing contract
		
		emit Withdraw(msg.sender, _stakeID, _toWithdraw, currentAmount);

		payable(msg.sender).transfer(userTokens);
    } 


	function selfHarvest(uint256[] calldata _stakeID, address _harvestInto) external {
        require(_stakeID.length <= userInfo[msg.sender].length, "incorrect Stake list");
        UserInfo[] storage user = userInfo[msg.sender];
        harvest();
        uint256 _toWithdraw = 0;
        uint256 _payout = 0;
 
        for(uint256 i = 0; i<_stakeID.length; i++) {
			payFee(user[_stakeID[i]]);
            _toWithdraw+= user[_stakeID[i]].amount * accDtxPerShare / 1e12 - user[_stakeID[i]].debt;
			user[_stakeID[i]].debt = user[_stakeID[i]].amount * accDtxPerShare / 1e12;
        }

        if(_harvestInto == msg.sender) {
            _payout = _toWithdraw * defaultDirectPayout / 10000;
            token.safeTransfer(msg.sender, _payout); 
		} else {
            require(poolPayout[_harvestInto].amount != 0, "incorrect pool!");
            _payout = _toWithdraw * poolPayout[_harvestInto].amount / 10000;
            IacPool(_harvestInto).giftDeposit(_payout, msg.sender, poolPayout[_harvestInto].minServe);
		}

        uint256 _penalty = _toWithdraw - _payout;
		token.safeTransfer(treasury, _penalty); //penalty to treasury

		emit SelfHarvest(msg.sender, _harvestInto, _payout, _penalty);        
    }


	// emergency withdraw, without caring about rewards
	function emergencyWithdraw(uint256 _stakeID) public {
		require(_stakeID < userInfo[msg.sender].length, "invalid stake ID");
		UserInfo storage user = userInfo[msg.sender][_stakeID];

        payFee(user);

		uint256 _amount = user.amount;
		
		_removeStake(msg.sender, _stakeID); //delete the stake
        emit Withdraw(msg.sender, _stakeID, 0, _amount);
		payable(msg.sender).transfer(_amount);
	}

	function emergencyWithdrawAll() external {
		uint256 _stakeID = userInfo[msg.sender].length;
		while(_stakeID > 0) {
			_stakeID--;
			emergencyWithdraw(_stakeID);
		}
	}
	
	function collectCommission(address[] calldata _beneficiary, uint256[][] calldata _stakeID) external nonReentrant {
		for(uint256 i = 0; i< _beneficiary.length; i++) {
			for(uint256 j = 0; j< _stakeID[i].length; i++) {
                UserInfo storage user = userInfo[_beneficiary[i]][j];
                payFee(user);
            }
		}
	}
	
	function collectCommissionAuto(address[] calldata _beneficiary) external nonReentrant {
		for(uint256 i = 0; i< _beneficiary.length; i++) {
			
			uint256 _nrOfStakes = getNrOfStakes(_beneficiary[i]);
			
			for(uint256 j = 0; j < _nrOfStakes; j++) {
                UserInfo storage user = userInfo[_beneficiary[i]][j];
                payFee(user);
            }
		}
		
	}


	// With "Virtual harvest" for external calls
	function virtualAccDtxPerShare() public view returns (uint256) {
		uint256 _pending = IMasterChef(masterchef).pendingEgg(poolID, address(this));
		return (accDtxPerShare + _pending * 1e12  / address(this).balance);
	}

    function viewStakeEarnings(address _user, uint256 _stakeID) external view returns (uint256) {
		UserInfo storage _stake = userInfo[_user][_stakeID];
        uint256 _pending = _stake.amount * virtualAccDtxPerShare() / 1e12 - _stake.debt;
        return _pending;
    }

    function viewUserTotalEarnings(address _user) external view returns (uint256) {
        UserInfo[] storage _stake = userInfo[_user];
        uint256 nrOfUserStakes = _stake.length;

		uint256 _totalPending = 0;
		
		for(uint256 i=0; i < nrOfUserStakes; i++) {
			_totalPending+= _stake[i].amount * virtualAccDtxPerShare() / 1e12 - _stake[i].debt;
		}
		
		return _totalPending;
    }
	//we want user deposit, we want total deposited, we want pending rewards, 
	function multiCall(address _user, uint256 _stakeID) external view returns(uint256, uint256, uint256, uint256) {
		UserInfo storage user = userInfo[_user][_stakeID];
		uint256 _pending = user.amount * virtualAccDtxPerShare() / 1e12 - user.debt;
		return(user.amount, user.feesPaid, address(this).balance, _pending);
	}

    /**
     * Returns number of stakes for a user
     */
    function getNrOfStakes(address _user) public view returns (uint256) {
        return userInfo[_user].length;
    }

    /**
     * @return Returns total pending dtx rewards
     */
    function calculateTotalPendingDTXRewards() external view returns (uint256) {
        return(IMasterChef(masterchef).pendingEgg(poolID, address(this)));
    }
	

	//public lookup for UI
    function publicBalanceOf() public view returns (uint256) {
        uint256 amount = IMasterChef(masterchef).pendingEgg(poolID, address(this)); 
        return token.balanceOf(address(this)) + amount; 
    }

	
	/*
	 * Unlikely, but Masterchef can be changed if needed to be used without changing pools
	 * masterchef = IMasterChef(token.owner());
	 * Must stop earning first(withdraw tokens from old chef)
	*/
	function setMasterChefAddress(IMasterChef _masterchef, uint256 _newPoolID) external adminOnly {
		masterchef = _masterchef;
		poolID = _newPoolID; //in case pool ID changes
		
		uint256 _dummyAllowance = IERC20(dummyToken).allowance(address(this), address(masterchef));
		if(_dummyAllowance == 0) {
			IERC20(dummyToken).safeApprove(address(_masterchef), type(uint256).max);
		}
	}
	
    /**
     * When contract is launched, dummyToken shall be deposited to start earning rewards
     */
    function startEarning() external adminOnly {
		IMasterChef(masterchef).deposit(poolID, dummyToken.balanceOf(address(this)));
    }
	
    /**
     * Dummy token can be withdrawn if ever needed(allows for flexibility)
     */
	function stopEarning(uint256 _withdrawAmount) external adminOnly {
		if(_withdrawAmount == 0) { 
			IMasterChef(masterchef).withdraw(poolID, dummyToken.balanceOf(address(masterchef)));
		} else {
			IMasterChef(masterchef).withdraw(poolID, _withdrawAmount);
		}
	}
	
    /**
     * Withdraws dummyToken to owner(who can burn it if needed)
     */
    function withdrawDummy(uint256 _amount) external adminOnly {	
        if(_amount == 0) { 
			dummyToken.safeTransfer(admin, dummyToken.balanceOf(address(this)));
		} else {
			dummyToken.safeTransfer(admin, _amount);
		}
    }
	
	
	/**
	 * option to withdraw wrongfully sent tokens(but requires change of the governing contract to do so)
	 * If you send wrong tokens to the contract address, consider them lost. Though there is possibility of recovery
	 */
	function withdrawStuckTokens(address _tokenAddress) external {
		require(_tokenAddress != address(token), "illegal token");
		require(_tokenAddress != address(dummyToken), "illegal token");
		
		IERC20(_tokenAddress).safeTransfer(IGovernor(admin).treasuryWallet(), IERC20(_tokenAddress).balanceOf(address(this)));
	}
    
    //need to set pools before launch or perhaps during contract launch
    //determines the payout depending on the pool. could set a governance process for it(determining amounts for pools)
	//allocation contract contains the decentralized proccess for updating setting, but so does the admin(governor)
    function setPoolPayout(address _poolAddress, uint256 _amount, uint256 _minServe) external adminOnly {
		if(_poolAddress == address(0)) {
			require(_amount <= 10000, "out of range");
			defaultDirectPayout = _amount;
		} else {
			require(_amount <= 10000, "out of range"); 
			poolPayout[_poolAddress].amount = _amount;
        	poolPayout[_poolAddress].minServe = _minServe; //mandatory lockup(else stake for 5yr, withdraw with 82% penalty and receive 18%)
		}
    }
    
    function updateSettings(uint256 _defaultDirectHarvest) external adminOnly {
        defaultDirectPayout = _defaultDirectHarvest;
    }

    /**
    *
    */
    function setAdmin() external {
        admin = IMasterChef(masterchef).owner();
    }
	
	function setTreasury(address _newTreasury) external adminOnly {
		treasury = _newTreasury;
	}
	
	function setDepositFee(uint256 _depositFee) external adminOnly {
        require(_depositFee <= maxFee, "out of limit");
		depositFee = _depositFee;
	}

    function setFundingRate(uint256 _fundingRate) external adminOnly {
        require(_fundingRate <= maxFundingFee, "out of limit");
		fundingRate = _fundingRate;
	}

    function setRefShare1(uint256 _refShare1) external adminOnly {
        require(_refShare1 <= 7500, "out of limit");
		refShare1 = _refShare1;
	}

    function setRefShare2(uint256 _refShare2) external adminOnly {
        require(_refShare2 <= 7500, "out of limit");
		refShare2 = _refShare2;
	}

    function payFee(UserInfo storage user) private {
		uint256 _lastAction = user.lastAction;
        uint256 secondsSinceLastaction = block.timestamp - _lastAction;
				
		if(secondsSinceLastaction >= 3600) {
			user.lastAction = block.timestamp - (secondsSinceLastaction % 3600);
			
			uint256 commission = (block.timestamp - _lastAction) / 3600 * user.amount * fundingRate / 100000;
			uint256 refEarning = 0;
			address _ref = user.referredBy;
			
			if(_ref != msg.sender) {
				refEarning = commission * refShare2 / 10000;
				payable(_ref).transfer(refEarning);
			}
			
			payable(treasury).transfer(commission - refEarning);

            user.feesPaid = user.feesPaid + commission;
			
			user.amount = user.amount - commission;
			
			emit CollectedFee(_ref, commission);
		}
	}


    /**
     * removes the stake
     */
    function _removeStake(address _staker, uint256 _stakeID) private {
        UserInfo[] storage stakes = userInfo[_staker];
        uint256 lastStakeID = stakes.length - 1;
        
        if(_stakeID != lastStakeID) {
            stakes[_stakeID] = stakes[lastStakeID];
        }
        
        stakes.pop();
    }
}
