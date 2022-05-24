// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.0;
import "./libs/standard/IERC20.sol"; //using standard contracts. Governor is NOT a trusted contract
import "./libs/standard/Address.sol";
import "./libs/standard/SafeERC20.sol"; 

interface IacPool {
    function setCallFee(uint256 _callFee) external;
    function totalShares() external returns (uint256);
    function totalVotesFor(uint256 proposalID) external returns (uint256);
    function setAdmin(address _admin, address _treasury) external;
    function setTreasury(address _treasury) external;
	function addAndExtendStake(address _recipientAddr, uint256 _amount, uint256 _stakeID, uint256 _lockUpTokensInSeconds) external;
    function giftDeposit(uint256 _amount, address _toAddress, uint256 _minToServeInSecs) external;
    function harvest() external returns (uint256);
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
}

interface IXVMCtreasury {
    function requestWithdraw(address _token, address _receiver, uint _value) external;
}

interface IOldChef {
	function burnTokens(uint256 _amount) external;
}

interface IConsensus {
	function totalXVMCStaked() external view returns(uint256);
	function tokensCastedPerVote(uint256 _forID) external view returns(uint256);
	function isGovInvalidated(address _failedGov) external view returns(bool, bool);
}

interface IPolygonMultisig {
	function isOwner(address) external view returns(bool);
}

interface IRewardBoost {
	function updateDelayBetweenEvents(uint256 _delay) external;
	function updateGrandEventLength(uint256 _length) external;
}

    /**
     * XVMC governor is a decentralized masterchef governed by it's users
     * Works as a decentralized cryptocurrency with no third-party control
     * Effectively creating a DAO through time-deposits
     *
     * In order to earn staking rewards, users must lock up their tokens.
     * Certificates of deposit or time deposit are the biggest market in the world
     * The longer the lockup period, the higher the rewards(APY) and voting power 
     * The locked up stakers create the governance council, through which
     * the protocol can be upgraded in a decentralized manner.
     *
     * Users are utilized as oracles through on-chain voting regulating the entire system(events,
     * rewards, APYs, fees, bonuses,...)
     * The token voting is overpowered by the consensus mechanism(locked up stakers)
     *
     * It is a real DAO creating an actual decentralized finance ecosystem
     *
     * https://macncheese.finance/
    */

    
contract XVMCgovernor {
    using SafeERC20 for IERC20;
    
    uint256 public immutable goldenRatio = 1618; //1.618 is the golden ratio
	address public immutable oldToken = 0x6d0c966c8A09e354Df9C48b446A474CE3343D912;
    address public immutable token = ENTERNEWTOKEN; //XVMC token
    
    //masterchef address
    address public immutable masterchef = ENTERNEWCHEF;
    address public immutable oldChefOwner = ENTERCONTRACTHATOWNSCHEF;
	
	//https://docs.polygon.technology/docs/faq/commit-chain-multisigs/
	address public immutable polygonMultisig = 0x355b8E02e7F5301E6fac9b7cAc1D6D9c86C0343f; 
	
    address public immutable consensusContract = ;
    address public immutable farmContract = ;
    address public immutable fibonacceningContract = ; //reward boost contract
    address public immutable basicContract = ;
	
	address public immutable nftAllocationContract = ;
    
    //Addresses for treasuryWallet and NFT wallet
    address public treasuryWallet = ;
    address public nftWallet = ;
    
    //addresses for time-locked deposits(autocompounding pools)
    address public immutable acPool1 = ;
    address public immutable acPool2 = ;
    address public immutable acPool3 = ;
    address public immutable acPool4 = ;
    address public immutable acPool5 = ;
    address public immutable acPool6 = ;
        
    //pool ID in the masterchef for respective Pool address and dummy token
    uint256 public immutable acPool1ID = 2;
    uint256 public immutable acPool2ID = 3;
    uint256 public immutable acPool3ID = 4;
    uint256 public immutable acPool4ID = 5;
    uint256 public immutable acPool5ID = 6;
    uint256 public immutable acPool6ID = 7;
	
	uint256 public immutable nftStakingPoolID = 10;
    
    mapping(address => uint256) private _rollBonus;
	
	mapping(address => address[]) public signaturesConfirmed; //for multi-sig
	mapping(address => mapping(address => bool)) public alreadySigned; //alreadySigned[owner][newGovernor]
    
    uint256 public costToVote = 500000 * 1e18;  // 500K coins. All proposals are valid unless rejected. This is a minimum to prevent spam
    uint256 public delayBeforeEnforce = 3 days; //minimum number of TIME between when proposal is initiated and executed

    uint256 public maximumVoteTokens; // maximum tokens that can be voted with to prevent tyrany
    
    //fibonaccening event can be scheduled once minimum threshold of tokens have been collected
    uint256 public thresholdFibonaccening = 10000000000 * 1e18; //10B coins
    
    //delays for Fibonnaccening Events
    uint256 public immutable minDelay = 1 days; // has to be called minimum 1 day in advance
    uint256 public immutable maxDelay = 31 days; //1month.. is that good? i think yes
    
    uint256 public rewardPerBlockPriorFibonaccening; //remembers the last reward used
    bool public eventFibonacceningActive; // prevent some functions if event is active ..threshold and durations for fibonaccening
    
    uint256 public blocksPerSecond = 434783; // divids with a million
    uint256 public durationForCalculation= 12 hours; //period used to calculate block time
    uint256  public lastBlockHeight; //block number when counting is activated
    uint256 public recordTimeStart; //timestamp when counting is activated
    bool public countingBlocks;

	bool public isInflationStatic; // if static, inflation stays perpetually at 1.618% annually. If dynamic, it reduces by 1.618% on each reward boost
    uint256  public totalFibonacciEventsAfterGrand; //used for rebalancing inflation after Grand Fib
    
    uint256 public newGovernorRequestBlock;
    address public eligibleNewGovernor; //used for changing smart contract
    bool public changeGovernorActivated;

	bool public fibonacciDelayed; //used to delay fibonaccening events through vote
	
	uint256 public lastHarvestedTime;

    event SetInflation(uint256 rewardPerBlock);
    event TransferOwner(address newOwner, uint256 timestamp);
    event EnforceGovernor(address _newGovernor, address indexed enforcer);
    event GiveRolloverBonus(address recipient, uint256 amount, address poolInto);
	event Harvest(address indexed sender, uint256 callFee);
	event Multisig(address signer, address newGovernor, bool sign, uint256 idToVoteFor);
    
    constructor(
		address _acPool1,
		address _acPool2,
		address _acPool3,
		address _acPool4,
		address _acPool5,
		address _acPool6) {
			_rollBonus[_acPool1] = 75;
			_rollBonus[_acPool2] = 100;
			_rollBonus[_acPool3] = 150;
			_rollBonus[_acPool4] = 250;
			_rollBonus[_acPool5] = 350;
			_rollBonus[_acPool6] = 500;
    }    

    
    /**
     * Updates circulating supply and maximum vote token variables
     */
    function updateMaximumVotetokens() external {
        maximumVoteTokens = getTotalSupply() / 10000;
    }
    

    /**
     * Calculates average block time
     * No decimals so we keep track of "100blocks" per second
	 * It will be used in the future to keep inflation static, while block production can be dynamic
	 * (bitcoin adjusts to 1 block per 10minutes, XVMC inflation is dependant on the production of blocks on Polygon which can vary)
     */
    function startCountingBlocks() external {
        require(!countingBlocks, "already counting blocks");
        countingBlocks = true;
        lastBlockHeight = block.number;
        recordTimeStart = block.timestamp;
    } 
    function calculateAverageBlockTime() external {
        require(countingBlocks && (recordTimeStart + durationForCalculation) <= block.timestamp);
        blocksPerSecond = 1000000 * (block.number - lastBlockHeight) / (block.timestamp - recordTimeStart);
        countingBlocks = false;
    }
    
    function getRollBonus(address _bonusForPool) external view returns (uint256) {
        return _rollBonus[_bonusForPool];
    }
    
    /**
     * Return total(circulating) supply.
     * Total supply = total supply of XVMC token(new) + (total supply of oldToken - supply of old token inside contract of new token) * 1000
	 * New XVMC token = 1000 * old token (can be swapped inside the token contract, contract holds old tokens)
	 * Old XVMC tokens held inside the contract of token are basically tokens that have been swapped to new token at a ratio of (1:1000)
    */
    function getTotalSupply() public view returns(uint256) {
        return (IERC20(token).totalSupply() +
					1000 * (IERC20(oldToken).totalSupply() - IERC20(oldToken).balanceOf(token)));
    }
    
    /**
     * Mass equivalent to massUpdatePools in masterchef, but only for relevant pools
    */
    function updateAllPools() external {
        IMasterChef(masterchef).updatePool(0); // XVMC-USDC and XVMC-wmatic
    	IMasterChef(masterchef).updatePool(1); 
    	IMasterChef(masterchef).updatePool(7); //meme pool 7,8
    	IMasterChef(masterchef).updatePool(8);
        IMasterChef(masterchef).updatePool(acPool1ID);
    	IMasterChef(masterchef).updatePool(acPool2ID); 
    	IMasterChef(masterchef).updatePool(acPool3ID); 
    	IMasterChef(masterchef).updatePool(acPool4ID); 
    	IMasterChef(masterchef).updatePool(acPool5ID); 
    	IMasterChef(masterchef).updatePool(acPool6ID); 
    }
    
     /**
     * Rebalances farms in masterchef
     */
    function rebalanceFarms() external {
    	IMasterChef(masterchef).updatePool(0);
    	IMasterChef(masterchef).updatePool(1); 
    }
   
     /**
     * Rebalances Pools and allocates rewards in masterchef
     * Pools with higher time-lock must always pay higher rewards in relative terms
     * Eg. for 1XVMC staked in the pool 6, you should always be receiving
     * 50% more rewards compared to staking in pool 4
     * 
     * QUESTION: should we create a modifier to prevent rebalancing during inflation events?
     * Longer pools compound on their interests and earn much faster?
     * On the other hand it could also be an incentive to hop to pools with longer lockup
	 * Could also make it changeable through voting
     */
    function rebalancePools() public {
    	uint256 balancePool1 = IERC20(token).balanceOf(acPool1);
    	uint256 balancePool2 = IERC20(token).balanceOf(acPool2);
    	uint256 balancePool3 = IERC20(token).balanceOf(acPool3);
    	uint256 balancePool4 = IERC20(token).balanceOf(acPool4);
    	uint256 balancePool5 = IERC20(token).balanceOf(acPool5);
    	uint256 balancePool6 = IERC20(token).balanceOf(acPool6);
    	
   	    uint256 total = balancePool1 + balancePool2 + balancePool3 + balancePool4 + balancePool5 + balancePool6;
    	
    	IMasterChef(masterchef).set(acPool1ID, (balancePool1 * 20000 / total), 0, false);
    	IMasterChef(masterchef).set(acPool2ID, (balancePool2 * 30000 / total), 0, false);
    	IMasterChef(masterchef).set(acPool3ID, (balancePool3 * 45000 / total), 0, false);
    	IMasterChef(masterchef).set(acPool4ID, (balancePool4 * 100000 / total), 0, false);
    	IMasterChef(masterchef).set(acPool5ID, (balancePool5 * 130000 / total), 0, false);
    	IMasterChef(masterchef).set(acPool6ID, (balancePool6 * 150000 / total), 0, false); 
    	
    	//equivalent to massUpdatePools() in masterchef, but we loop just through relevant pools
    	IMasterChef(masterchef).updatePool(acPool1ID);
    	IMasterChef(masterchef).updatePool(acPool2ID); 
    	IMasterChef(masterchef).updatePool(acPool3ID); 
    	IMasterChef(masterchef).updatePool(acPool4ID); 
    	IMasterChef(masterchef).updatePool(acPool5ID); 
    	IMasterChef(masterchef).updatePool(acPool6ID); 
    }

    /**
     * Harvests from all pools and rebalances rewards
     */
    function harvest() external {
        require(msg.sender == tx.origin, "no proxy/contracts");

        uint256 totalFee = IacPool(acPool1).harvest() + IacPool(acPool2).harvest() + IacPool(acPool3).harvest() +
        					IacPool(acPool4).harvest() + IacPool(acPool5).harvest() + IacPool(acPool6).harvest();

        rebalancePools();
		
		lastHarvestedTime = block.timestamp;
	
		IERC20(token).safeTransfer(msg.sender, totalFee);

		emit Harvest(msg.sender, totalFee);
    }
	
	function pendingharvestRewards() external view returns (uint256) {
		uint256 totalRewards = IacPool(acPool1).calculateHarvestXVMCRewards() + IacPool(acPool2).calculateHarvestXVMCRewards() + IacPool(acPool3).calculateHarvestXVMCRewards() +
        					IacPool(acPool4).calculateHarvestXVMCRewards() + IacPool(acPool5).calculateHarvestXVMCRewards() + IacPool(acPool6).calculateHarvestXVMCRewards();
		return totalRewards;
	}
    
    /**
     * Mechanism, where the governor gives the bonus 
     * to user for extending(re-commiting) their stake
     * tldr; sends the gift deposit, which resets the timer
     * the pool is responsible for calculating the bonus
     */
    function stakeRolloverBonus(address _toAddress, address _depositToPool, uint256 _bonusToPay, uint256 _stakeID) external {
        require(
            msg.sender == acPool1 || msg.sender == acPool2 || msg.sender == acPool3 ||
            msg.sender == acPool4 || msg.sender == acPool5 || msg.sender == acPool6);
        
        IacPool(_depositToPool).addAndExtendStake(_toAddress, _bonusToPay, _stakeID, 0);
        
        emit GiveRolloverBonus(_toAddress, _bonusToPay, _depositToPool);
    }

    /**
     * Sets inflation in Masterchef
     */
    function setInflation(uint256 rewardPerBlock) external {
        require(msg.sender == fibonacceningContract);
    	IMasterChef(masterchef).updateEmissionRate(rewardPerBlock);
        rewardPerBlockPriorFibonaccening = rewardPerBlock; //remember last inflation
        
        emit SetInflation(rewardPerBlock);
    }
    
    
    function enforceGovernor() external {
        require(msg.sender == consensusContract);
		require(newGovernorRequestBlock + 269420 < block.number, "time delay not yet passed");

		IMasterChef(masterchef).setFeeAddress(eligibleNewGovernor);
        IMasterChef(masterchef).dev(eligibleNewGovernor);
        IMasterChef(masterchef).transferOwnership(eligibleNewGovernor); //transfer masterchef ownership
		
		IERC20(token).safeTransfer(eligibleNewGovernor, IERC20(token).balanceOf(address(this))); // send collected XVMC tokens to new governor
        
		emit EnforceGovernor(eligibleNewGovernor, msg.sender);
    }
	
    function setNewGovernor(address beneficiary) external {
        require(msg.sender == consensusContract);
        newGovernorRequestBlock = block.number;
        eligibleNewGovernor = beneficiary;
        changeGovernorActivated = true;
    }
	
	function governorRejected() external {
		require(changeGovernorActivated, "not active");
		
		(bool _govInvalidated, ) = IConsensus(consensusContract).isGovInvalidated(eligibleNewGovernor);
		if(_govInvalidated) {
			changeGovernorActivated = false;
		}
	}

	function treasuryRequest(address _tokenAddr, address _recipient, uint256 _amountToSend) external {
		require(msg.sender == consensusContract);
		IXVMCtreasury(treasuryWallet).requestWithdraw(
			_tokenAddr, _recipient, _amountToSend
		);
	}
	
	function updateDurationForCalculation(uint256 _newDuration) external {
	    require(msg.sender == basicContract);
	    durationForCalculation = _newDuration;
	}
	
	function delayFibonacci(bool _arg) external {
	    require(msg.sender == consensusContract);
	    fibonacciDelayed = _arg;
	}
	
	function setActivateFibonaccening(bool _arg) external {
		require(msg.sender == fibonacceningContract);
		eventFibonacceningActive = _arg;
	}

	function setPool(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) external {
	    require(msg.sender == farmContract);
	    IMasterChef(masterchef).set(_pid, _allocPoint, _depositFeeBP, _withUpdate);
	}
	
	function setThresholdFibonaccening(uint256 newThreshold) external {
	    require(msg.sender == basicContract);
	    thresholdFibonaccening = newThreshold;
	}
	
	function updateDelayBeforeEnforce(uint256 newDelay) external {
	    require(msg.sender == basicContract);
	    delayBeforeEnforce = newDelay;
	}
	
	function setCallFee(address _acPool, uint256 _newCallFee) external {
	    require(msg.sender == basicContract);
	    IacPool(_acPool).setCallFee(_newCallFee);
	}
	
	function updateCostToVote(uint256 newCostToVote) external {
	    require(msg.sender == basicContract);
	    costToVote = newCostToVote;
	}
	
	function updateRolloverBonus(address _forPool, uint256 _bonus) external {
	    require(msg.sender == basicContract);
		require(_bonus <= 1500, "15% hard limit");
	    _rollBonus[_forPool] = _bonus;
	}
	
	function burnFromOldChef(uint256 _amount) external {
		require(msg.sender == farmContract || msg.sender == fibonacceningContract);
		IOldChef(oldChefOwner).burnTokens(_amount);
	}
	
	function setGovernorTax(uint256 _amount) external {
		require(msg.sender == farmContract);
		IMasterChef(masterchef).setGovernorFee(_amount);
	}
	
	function postGrandFibIncreaseCount() external {
		require(msg.sender == fibonacceningContract);
		totalFibonacciEventsAfterGrand++;
	}
	
	function updateDelayBetweenEvents(uint256 _amount) external {
	    require(msg.sender == basicContract);
		IRewardBoost(fibonacceningContract).updateDelayBetweenEvents(_amount);
	}
	function updateGrandEventLength(uint256 _amount) external {
	    require(msg.sender == basicContract);
		IRewardBoost(fibonacceningContract).updateGrandEventLength(_amount);
	}
	    
	
    /**
     * Transfers collected fees into treasury wallet(but not XVMC...for now)
     */
    function transferCollectedFees(address _tokenContract) external {
        require(msg.sender == tx.origin);
		require(_tokenContract != token, "not XVMC!");
		
        uint256 amount = IERC20(_tokenContract).balanceOf(address(this));
        
        IERC20(_tokenContract).safeTransfer(treasuryWallet, amount);
    }

    
    /**
     * The weak point, Polygon-ETH bridge is secured by a 5/8 multisig.
	 * Can change governing contract thru a multisig(without consensus) and 42% of weighted votes voting in favor
	 * https://docs.polygon.technology/docs/faq/commit-chain-multisigs/
     */
    function multiSigGovernorChange(address _newGovernor) external {
		uint _signatureCount = 0;
		uint _ownersLength = signaturesConfirmed[_newGovernor].length;
		require(_ownersLength >= 5, "minimum 5 signatures required");
		for(uint i=0; i< _ownersLength; i++) {//owners can change, must check if still active
			if(IPolygonMultisig(polygonMultisig).isOwner(signaturesConfirmed[_newGovernor][i])) {
				_signatureCount++;
			}
		}
        require(_signatureCount >= 5, "Minimum 5/8 signatures required");
		
		uint256 _totalStaked = IConsensus(consensusContract).totalXVMCStaked();
		uint256 _totalVotedInFavor = IConsensus(consensusContract).tokensCastedPerVote(uint256(uint160(_newGovernor)));
		
		require(_totalVotedInFavor >= (_totalStaked * 42 / 100), "Minimum 42% weighted vote required");
        
        IMasterChef(masterchef).setFeeAddress(_newGovernor);
        IMasterChef(masterchef).dev(_newGovernor);
        IMasterChef(masterchef).transferOwnership(_newGovernor);
		IERC20(token).safeTransfer(_newGovernor, IERC20(token).balanceOf(address(this)));
    }

	function signMultisig(address _newGovernor) external {
		bool _isOwner = IPolygonMultisig(polygonMultisig).isOwner(msg.sender);
		require(_isOwner, "Signer is not multisig owner");
		
		require(!alreadySigned[msg.sender][_newGovernor], "already signed");
		alreadySigned[msg.sender][_newGovernor] = true;
		signaturesConfirmed[_newGovernor].push(msg.sender); //adds vote
		
		emit Multisig(msg.sender, _newGovernor, true, uint256(uint160(_newGovernor)));
	}
	
	function unSignMultisig(address _newGovernor) external {
		require(alreadySigned[msg.sender][_newGovernor], "not signed");
		uint256 _lastIndex = signaturesConfirmed[_newGovernor].length - 1;
		uint256 _index;
		while(signaturesConfirmed[_newGovernor][_index] != msg.sender) {
			_index++;
		}
		alreadySigned[msg.sender][_newGovernor] = false;
		if(_index != _lastIndex) {
			signaturesConfirmed[_newGovernor][_index] = signaturesConfirmed[_newGovernor][_lastIndex];
		} 
		signaturesConfirmed[_newGovernor].pop();
		
		emit Multisig(msg.sender, _newGovernor, false, uint256(uint160(_newGovernor)));
	}
	
	function addressToUint256(address _address) external pure returns(uint256) {
		return(uint256(uint160(_address)));
	}
    
}  
