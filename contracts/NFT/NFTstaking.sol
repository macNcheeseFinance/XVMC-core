// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.1;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.0/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721Receiver.sol";

interface IMasterChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function pendingEgg(uint256 _pid, address _user) external view returns (uint256);
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function emergencyWithdraw(uint256 _pid) external;
    function feeAddress() external view returns (address);
    function owner() external view returns (address);
}

interface IGovernance {
    function rebalancePools() external;
    function nftAllocationContract() external view returns (address);
    function treasuryWallet() external view returns (address);
}

interface IVoting {
    function addCredit(uint256 amount, address _beneficiary) external;
}

interface IacPool {
    function giftDeposit(uint256 _amount, address _toAddress, uint256 _minToServeInSecs) external;
}

interface INFTallocation {
    function nftAllocation(address _tokenAddress, uint256 _tokenID, address _allocationContract) external view returns (uint256);
}

/**
 * XVMC NFT staking contract
 * !!! Warning: !!! Licensed under Business Source License 1.1 (BSL 1.1)
 */
contract XVMCtimeDeposit is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserInfo {
        address tokenAddress;
        uint256 tokenID;
        uint256 shares; // number of shares the NFT is worth in the pool
        uint256 debt; //the allocation for the NFT at the time of deposit(why named debt? idk)
        //basically debt because it counts as "artificial tokens"(we deposit a singular NFT worth an artificial amount)
        //simple substitute for using NFTs instead of regular tokens
    }
    struct UserSettings {
        address pool; //which pool to payout in
        uint256 harvestThreshold;
        uint256 feeToPay;
    }
    struct PoolPayout {
        uint256 amount;
        uint256 minServe;
    }

    IERC20 public immutable token; // XVMC token
	
	IERC20 public immutable oldToken = IERC20(0x6d0c966c8A09e354Df9C48b446A474CE3343D912);
    
    IERC20 public immutable dummyToken; 

    IMasterChef public masterchef;  

    mapping(address => UserInfo[]) public userInfo;
    mapping(address => UserSettings) public userSettings; 
    mapping(address => PoolPayout) public poolPayout; //determines the percentage received depending on withdrawal option
 
	uint256 public poolID; 
    uint256 public totalShares;
    address public admin; //admin = governing contract!
    address public treasury; //penalties
    address public allocationContract; // PROXY CONTRACT for looking up allocations

    address public votingCreditAddress;

    uint256 public tokenDebt; //sum of allocations of all deposited NFTs

    //if user settings not set, use default
    address defaultHarvest; //pool address to harvest into
    uint256 defaultHarvestThreshold = 1000000;
    uint256 defaultFeeToPay = 250; //fee for calling 2.5% default

    uint256 defaultDirectPayout = 500; //5% if withdrawn into wallet

    event Deposit(address indexed tokenAddress, uint256 tokenID, address indexed depositor, uint256 shares, uint256 nftAllocation);
    event Withdraw(address indexed sender, uint256 stakeID, address token, uint256 tokenID, uint256 shares, uint256 harvestAmount);
    event UserSettingUpdate(address user, address poolAddress, uint256 threshold, uint256 feeToPay);

    event AddVotingCredit(address indexed user, uint256 amount);
    /**
     * @notice Constructor
     * @param _token: XVMC token contract
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
        address _treasury,
        uint256 _poolID,
        address _allocationContract
    ) {
        token = _token;
        dummyToken = _dummyToken;
        masterchef = _masterchef;
        admin = _admin;
        treasury = _treasury;
        poolID = _poolID;
        allocationContract = _allocationContract;

        IERC20(_dummyToken).safeApprove(address(_masterchef), type(uint256).max);
    }
    
    /**
     * @notice Checks if the msg.sender is the admin
     */
    modifier adminOnly() {
        require(msg.sender == admin, "admin: wut?");
        _;
    }
	
    /**
     * Creates a NEW stake
     */
    function deposit(address _tokenAddress, uint256 _tokenID, address _allocationContract) external nonReentrant {
    	uint256 _allocationAmount = INFTallocation(allocationContract).nftAllocation(_tokenAddress, _tokenID, _allocationContract);
        require(_allocationAmount > 0, "Invalid NFT, no allocation");
        harvest();
        uint256 pool = balanceOf();
        IERC721(_tokenAddress).safeTransferFrom(msg.sender, address(this), _tokenID);
        uint256 currentShares = 0;
        if (totalShares != 0) {
            currentShares = (_allocationAmount * totalShares) / (pool);
        } else {
            currentShares = _allocationAmount;
        }
        
        totalShares = totalShares + currentShares;
        tokenDebt = tokenDebt + _allocationAmount;
        
        userInfo[msg.sender].push(
                UserInfo(_tokenAddress, _tokenID, currentShares, _allocationAmount)
            );

        emit Deposit(_tokenAddress, _tokenID, msg.sender, currentShares, _allocationAmount);
    }

	
    /**
     * Harvests into pool
     */
    function harvest() public {
        IMasterChef(masterchef).withdraw(poolID, 0);
    }
  
    /**
    *
    */
    function setAdmin() external {
        admin = IMasterChef(masterchef).owner();
        treasury = IMasterChef(masterchef).feeAddress();
    }
    
    function updateAllocationContract() external {
        allocationContract = IGovernance(admin).nftAllocationContract();
    }

    /**
     * @notice Withdraws the NFT and harvests earnings
     */
    function withdraw(uint256 _stakeID, address _harvestInto) public nonReentrant {
        harvest();
        require(_stakeID < userInfo[msg.sender].length, "invalid stake ID");
        UserInfo storage user = userInfo[msg.sender][_stakeID];

        uint256 currentAmount = (balanceOf() * (maxHarvest(user))) / (totalShares);
        totalShares = totalShares - user.shares;
        tokenDebt = tokenDebt - user.debt;

        uint256 _tokenID = user.tokenID;

		emit Withdraw(msg.sender, _stakeID, user.tokenAddress, _tokenID, user.shares, currentAmount);
		
        _removeStake(msg.sender, _stakeID); //delete the stake

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

        IERC721(user.tokenAddress).safeTransferFrom(address(this), msg.sender, _tokenID); //withdraw NFT
    } 

    function setUserSettings(address _poolAddress, uint256 _harvestThreshold, uint256 _feeToPay, address _harvestInto) external {
        require(_feeToPay <= 3000, "max 30%");
        if(_harvestInto != msg.sender) { require(poolPayout[_harvestInto].amount != 0, "incorrect pool!"); }
        UserSettings storage _setting = userSettings[msg.sender];
        _setting.harvestThreshold = _harvestThreshold;
        _setting.feeToPay = _feeToPay;
        _setting.pool = _harvestInto; //default pool to harvest into(or payout directly)
        emit UserSettingUpdate(msg.sender, _poolAddress, _harvestThreshold, _feeToPay);
    }

    //harvest own earnings
    //shares left MUST cover the user debt
    //_harvestInto are only trusted pools, no need for nonReentrant
    function selfHarvest(address _harvestInto) external {
        UserInfo[] storage user = userInfo[msg.sender];
		require(user.length > 0, "user has no stakes");
        harvest();
        uint256 _totalWithdraw = 0;
        uint256 _toWithdraw = 0;
        uint256 _payout = 0;
 
        for(uint256 i = 0; i<user.length; i++) {
            _toWithdraw = maxHarvest(user[i]); //SHARES
            user[i].shares = user[i].shares - _toWithdraw;
            _totalWithdraw+= _toWithdraw;
        }

        if(_harvestInto == msg.sender) {
            _toWithdraw = (balanceOf() * _totalWithdraw) / totalShares;
            _payout = _toWithdraw * defaultDirectPayout / 10000;
            token.safeTransfer(msg.sender, _payout); 
        } else {
            require(poolPayout[_harvestInto].amount != 0, "incorrect pool!");
            _toWithdraw = (balanceOf() * _totalWithdraw) / totalShares;
            _payout = _toWithdraw * poolPayout[_harvestInto].amount / 10000;
            IacPool(_harvestInto).giftDeposit(_toWithdraw, msg.sender, poolPayout[_harvestInto].minServe);
        }
        totalShares = totalShares - _totalWithdraw;
        token.safeTransfer(treasury, (_toWithdraw - _payout)); //penalty to treasury
    }
	//copy+paste of the previous function, can harvest custom stake ID
	//In case user has too many stakes, or if some are not worth harvesting
	function selfHarvestCustom(uint256[] calldata _stakeID, address _harvestInto) external {
        require(_stakeID.length <= userInfo[msg.sender].length, "incorrect Stake list");
        UserInfo[] storage user = userInfo[msg.sender];
        harvest();
        uint256 _totalWithdraw = 0;
        uint256 _toWithdraw = 0;
        uint256 _payout = 0;
 
        for(uint256 i = 0; i<_stakeID.length; i++) {
            _toWithdraw = maxHarvest(user[_stakeID[i]]); //SHARES
            user[_stakeID[i]].shares = user[_stakeID[i]].shares - _toWithdraw;
            _totalWithdraw+= _toWithdraw;
        }

        if(_harvestInto == msg.sender) {
            _toWithdraw = (balanceOf() * _totalWithdraw) / totalShares;
            _payout = _toWithdraw * defaultDirectPayout / 10000;
            token.safeTransfer(msg.sender, _payout); 
        } else {
            require(poolPayout[_harvestInto].amount != 0, "incorrect pool!");
            _toWithdraw = (balanceOf() * _totalWithdraw) / totalShares;
            _payout = _toWithdraw * poolPayout[_harvestInto].amount / 10000;
            IacPool(_harvestInto).giftDeposit(_toWithdraw, msg.sender, poolPayout[_harvestInto].minServe);
        }
        totalShares = totalShares - _totalWithdraw;
        token.safeTransfer(treasury, (_toWithdraw - _payout)); //penalty to treasury
    }

    //harvest earnings of another user(receive fees)
    function proxyHarvest(address _beneficiary) external {
        UserInfo[] storage user = userInfo[_beneficiary];
		require(user.length > 0, "user has no stakes");
        harvest();
        uint256 _totalWithdraw = 0;
        uint256 _toWithdraw = 0;
        uint256 _payout = 0;

        UserSettings storage _userSetting = userSettings[_beneficiary];

        address _harvestInto = _userSetting.pool;
        uint256 _minThreshold = _userSetting.harvestThreshold;
        uint256 _callFee = _userSetting.feeToPay;

        if(_minThreshold == 0) { _minThreshold = defaultHarvestThreshold; }
        if(_callFee == 0) { _callFee = defaultFeeToPay; }

        for(uint256 i = 0; i<user.length; i++) {
            _toWithdraw = maxHarvest(user[i]); //SHARES
            user[i].shares = user[i].shares - _toWithdraw;
            _totalWithdraw+= _toWithdraw;
        }

        if(_harvestInto == _beneficiary) {
            //fee paid to harvester
            _toWithdraw = (balanceOf() * _totalWithdraw) / totalShares;
            _payout = _toWithdraw * defaultDirectPayout / 10000;
            _callFee = _payout * _callFee / 10000;
            token.safeTransfer(msg.sender, _callFee); 
            token.safeTransfer(_beneficiary, (_payout - _callFee)); 
        } else {
            if(_harvestInto == address(0)) {
                _harvestInto = defaultHarvest; //default pool
            } //harvest Into is correct(checks if valid when user initiates the setting)
            
            _toWithdraw = (balanceOf() * _totalWithdraw) / totalShares;
            _payout = _toWithdraw * poolPayout[_harvestInto].amount / 10000;
            require(_payout > _minThreshold, "minimum threshold not met");
            _callFee = _payout * _callFee / 10000;
            token.safeTransfer(msg.sender, _callFee); 
            IacPool(_harvestInto).giftDeposit((_payout - _callFee), _beneficiary, poolPayout[_harvestInto].minServe);
        }
        totalShares = totalShares - _totalWithdraw;
        token.safeTransfer(treasury, (_toWithdraw - _payout)); //penalty to treasury
    }
	//copy+paste of the previous function, can harvest custom stake ID
	//In case user has too many stakes, or if some are not worth harvesting
	function proxyHarvestCustom(address _beneficiary, uint256[] calldata _stakeID) external {
        require(_stakeID.length <= userInfo[_beneficiary].length, "incorrect Stake list");
        UserInfo[] storage user = userInfo[_beneficiary];
        harvest();
        uint256 _totalWithdraw = 0;
        uint256 _toWithdraw = 0;
        uint256 _payout = 0;

        UserSettings storage _userSetting = userSettings[_beneficiary];

        address _harvestInto = _userSetting.pool;
        uint256 _minThreshold = _userSetting.harvestThreshold;
        uint256 _callFee = _userSetting.feeToPay;

        if(_minThreshold == 0) { _minThreshold = defaultHarvestThreshold; }
        if(_callFee == 0) { _callFee = defaultFeeToPay; }

        for(uint256 i = 0; i<_stakeID.length; i++) {
            _toWithdraw = maxHarvest(user[_stakeID[i]]); //SHARES
            user[_stakeID[i]].shares = user[_stakeID[i]].shares - _toWithdraw;
            _totalWithdraw+= _toWithdraw;
        }

        if(_harvestInto == _beneficiary) {
            //fee paid to harvester
            _toWithdraw = (balanceOf() * _totalWithdraw) / totalShares;
            _payout = _toWithdraw * defaultDirectPayout / 10000;
            _callFee = _payout * _callFee / 10000;
            token.safeTransfer(msg.sender, _callFee); 
            token.safeTransfer(_beneficiary, (_payout - _callFee)); 
        } else {
            if(_harvestInto == address(0)) {
                _harvestInto = defaultHarvest; //default pool
            } //harvest Into is correct(checks if valid when user initiates the setting)
            
            _toWithdraw = (balanceOf() * _totalWithdraw) / totalShares;
            _payout = _toWithdraw * poolPayout[_harvestInto].amount / 10000;
            require(_payout > _minThreshold, "minimum threshold not met");
            _callFee = _payout * _callFee / 10000;
            token.safeTransfer(msg.sender, _callFee); 
            IacPool(_harvestInto).giftDeposit((_payout - _callFee), _beneficiary, poolPayout[_harvestInto].minServe);
        }
        totalShares = totalShares - _totalWithdraw;
        token.safeTransfer(treasury, (_toWithdraw - _payout)); //penalty to treasury
    }

    //NOT COUNTING IN min withdraw, just based on shares
    //calculates amount of shares that cover the debt. Subtract from total to get maximum harvest amount
    function maxHarvest(UserInfo memory _user) public view returns (uint256) {
        uint256 _maximum = (_user.debt * totalShares) / balanceOf();
        return (_user.shares - _maximum - 1);
    }
    
    function viewStakeEarnings(address _user, uint256 _stakeID) external view returns (uint256) {
        uint256 _tokens = (balanceOf() * userInfo[_user][_stakeID].shares) / totalShares;
        return(_tokens - userInfo[_user][_stakeID].debt);
    }

    function viewUserTotalEarnings(address _user) external view returns (uint256) {
        (uint256 _userShares, uint256 _userDebt) = getUserTotals(_user);
        //convert shares into tokens and deduct debt
        uint256 _tokens = (balanceOf() * _userShares) / totalShares;
        return (_tokens - _userDebt);
    }
	
    /**
     * Ability to withdraw tokens from the stake, and add voting credit
     * At the time of launch there is no option(voting with credit), but can be added later on
    */
	function votingCredit(uint256 _shares, uint256 _stakeID) public {
        require(votingCreditAddress != address(0), "disabled");
        require(_stakeID < userInfo[msg.sender].length, "invalid stake ID");
		
		harvest();
        
        UserInfo storage user = userInfo[msg.sender][_stakeID];
        require(_shares < maxHarvest(user), "insufficient shares");

        uint256 currentAmount = (balanceOf() * (_shares)) / (totalShares);
        user.shares = user.shares - _shares;
        totalShares = totalShares - _shares;
		
        token.safeTransfer(votingCreditAddress, currentAmount);
		IVoting(votingCreditAddress).addCredit(currentAmount, msg.sender); //in the votingCreditAddress regulate how much is credited, depending on where it's coming from (msg.sender)

        emit AddVotingCredit(msg.sender, currentAmount);
    } 

	function cashoutAllToCredit() external {
        require(votingCreditAddress != address(0), "disabled");
        require(userInfo[msg.sender].length > 0, "no active stakes");
		
		harvest();

        uint256 _toWithdraw = 0;
        uint256 _totalWithdraw = 0;
        UserInfo[] storage user = userInfo[msg.sender];

        for(uint256 i=0; i<user.length; i++) {
            _toWithdraw = maxHarvest(user[i]); //SHARES
            user[i].shares = user[i].shares - _toWithdraw;
            _totalWithdraw+= _toWithdraw;
        }
        uint256 currentAmount = (balanceOf() * (_totalWithdraw)) / (totalShares);
        totalShares = totalShares - _totalWithdraw;
		
        token.safeTransfer(votingCreditAddress, currentAmount);
		IVoting(votingCreditAddress).addCredit(currentAmount, msg.sender); //in the votingCreditAddress regulate how much is credited, depending on where it's coming from (msg.sender)

        emit AddVotingCredit(msg.sender, currentAmount);
    } 

    //if allocation for the NFT changes, anyone can rebalance
    function rebalanceNFT(address _staker, uint256 _stakeID, address _allocationContract) external {
		harvest();
        UserInfo storage user = userInfo[_staker][_stakeID];
        uint256 _alloc = INFTallocation(allocationContract).nftAllocation(user.tokenAddress, user.tokenID, _allocationContract);
        if(_alloc == 0) { //no longer valid, anyone can push out and withdraw NFT to the owner (copy+paste withdraw option)
            require(_stakeID < userInfo[_staker].length, "invalid stake ID");

            uint256 currentAmount = (balanceOf() * (maxHarvest(user))) / (totalShares);
            totalShares = totalShares - user.shares;
            tokenDebt = tokenDebt - user.debt;

            uint256 _tokenID = user.tokenID;

            emit Withdraw(_staker, _stakeID, user.tokenAddress, _tokenID, user.shares, currentAmount);
            
            _removeStake(_staker, _stakeID); //delete the stake

            address _harvestInto = userSettings[_staker].pool;
            if(_harvestInto == address(0)) { _harvestInto = defaultHarvest; } 

            uint256 _toWithdraw;      
            if(_harvestInto == _staker) { 
                _toWithdraw = currentAmount * defaultDirectPayout / 10000;
                currentAmount = currentAmount - _toWithdraw;
                token.safeTransfer(_staker, _toWithdraw);
            } else {
                _toWithdraw = currentAmount * poolPayout[_harvestInto].amount / 10000;
                currentAmount = currentAmount - _toWithdraw;
                IacPool(_harvestInto).giftDeposit(_toWithdraw, _staker, poolPayout[_harvestInto].minServe);
            }
            token.safeTransfer(treasury, currentAmount); //penalty goes to governing contract

            IERC721(user.tokenAddress).safeTransferFrom(address(this), _staker, _tokenID); //withdraw NFT
        } else if(_alloc != user.debt) { //change allocation
            uint256 _profitShares = maxHarvest(user); 
            uint256 _profitTokens = (balanceOf() * _profitShares) / totalShares;
            //artificial withdraw, then re-deposit with new allocaiton, along with profited tokens
            totalShares = totalShares - user.shares; //as if ALL shares and ALL DEBT was withdrawn (actual profit tokens remain inside!)
            tokenDebt = tokenDebt - user.debt;
            user.shares = ((_alloc+_profitTokens) * totalShares) / (balanceOf() - _profitTokens); 
            tokenDebt = tokenDebt + _alloc;
            user.debt = _alloc;
            totalShares = totalShares + user.shares;
        }
    }

    //need to set pools before launch or perhaps during contract launch
    //determines the payout depending on the pool. could set a governance process for it(determining amounts for pools)
    function setPoolPayout(address _poolAddress, uint256 _amount, uint256 _minServe) external {
        require(msg.sender == allocationContract, "must be set by allocation contract");
		if(_poolAddress == address(0)) {
			require(_amount <= 10000, "out of range");
			defaultDirectPayout = _amount;
		} else if (_poolAddress == address(1)) {
			defaultHarvestThreshold = _amount;
		} else if (_poolAddress == address(2)) {
			require(_amount <= 1000, "out of range"); //max 10%
			defaultFeeToPay = _amount;
		} else {
			require(_amount <= 10000, "out of range"); 
			poolPayout[_poolAddress].amount = _amount;
        	poolPayout[_poolAddress].minServe = _minServe; //mandatory lockup(else stake for 5yr, withdraw with 82% penalty and receive 18%)
		}
    }
    
    function updateSettings(address _defaultHarvest, uint256 _threshold, uint256 _defaultFee, uint256 _defaultDirectHarvest) external adminOnly {
        defaultHarvest = _defaultHarvest; //longest pool should be the default
        defaultHarvestThreshold = _threshold;
        defaultFeeToPay = _defaultFee;
        defaultDirectPayout = _defaultDirectHarvest;
    }

    function updateVotingCreditAddress(address _newAddress) external adminOnly {
        votingCreditAddress = _newAddress;
    }

    /**
     * Returns number of stakes for a user
     */
    function getNrOfStakes(address _user) public view returns (uint256) {
        return userInfo[_user].length;
    }
    
    /**
     * Returns all shares and debt for a user
     */
    function getUserTotals(address _user) public view returns (uint256, uint256) {
        UserInfo[] storage _stake = userInfo[_user];
        uint256 nrOfUserStakes = _stake.length;

		uint256 countShares = 0;
        uint256 countDebt = 0;
		
		for(uint256 i=0; i < nrOfUserStakes; i++) {
			countShares += _stake[i].shares;
            countDebt += _stake[i].debt;
		}
		
		return (countShares, countDebt);
    }
	

    /**
     * @return Returns total pending xvmc rewards
     */
    function calculateTotalPendingXVMCRewards() external view returns (uint256) {
        return(IMasterChef(masterchef).pendingEgg(poolID, address(this)));
    }

    /**
     * @notice Calculates the price per share
     */
    function getPricePerFullShare() external view returns (uint256) {
        return totalShares == 0 ? 1e18 : balanceOf() * (1e18) / (totalShares);
    }
    
    /**
     * @notice returns number of shares for a certain stake of an user
     */
    function getUserShares(address _wallet, uint256 _stakeID) public view returns (uint256) {
        return userInfo[_wallet][_stakeID].shares;
    }
	
    /**
     * calculates pending rewards + balance of tokens in this address + artificial token debt(how much each NFT is worth)
	 * we harvest before every action, pending rewards not needed
     */
    function balanceOf() internal view returns (uint256) {
        return token.balanceOf(address(this)) + tokenDebt; 
    }
	//public lookup for UI
    function publicBalanceOf() public view returns (uint256) {
        uint256 amount = IMasterChef(masterchef).pendingEgg(poolID, address(this)); 
        return token.balanceOf(address(this)) + amount + tokenDebt; 
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
	function withdrawStuckTokens(address _tokenAddress) external adminOnly {
		require(_tokenAddress != address(token), "wrong token");
		require(_tokenAddress != address(dummyToken), "wrong token");
		
		IERC20(_tokenAddress).safeTransfer(IGovernance(admin).treasuryWallet(), IERC20(_tokenAddress).balanceOf(address(this)));
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
