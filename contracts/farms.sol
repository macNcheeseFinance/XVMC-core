// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libs/custom/IERC20.sol";
import "./libs/standard/Address.sol";
import "./libs/custom/SafeERC20.sol";

interface IXVMCgovernor {
    function costToVote() external returns (uint256);
    function maximumVoteTokens() external returns (uint256);
    function delayBeforeEnforce() external returns (uint256);
    function setPool(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) external; 
    function changeGovernorEnforced() external returns (bool);
    function eligibleNewGovernor() external returns (address);
    function setDurationForCalculation(uint256 _newDuration) external;
    function updateAllPools() external;
	function treasuryWallet() external view returns (address);
	function burnFromOldChef(uint256 _amount) external;
	function setGovernorTax(uint256 _amount) external;
	function eventFibonacceningActive() external view returns (bool);
}

interface IMasterChef {
    function totalAllocPoint() external returns (uint256);
    function poolInfo(uint256) external returns (address, uint256, uint256, uint256, uint16);
    function XVMCPerBlock() external returns (uint256);
    function owner() external view returns (address);
	function massUpdate() external;
}

interface IOldChefOwner {
	function burnDelay() external view returns(uint256);
}

interface IToken {
    function governor() external view returns (address);
	function owner() external view returns (address);
}

//contract that regulates the farms for XVMC
contract XVMCfarms is Ownable {
    using SafeERC20 for IERC20;
    
	struct ProposalFarm {
        bool valid;
        uint256 poolid;
        uint256 newAllocation;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
        uint256 firstCallTimestamp;
        uint16 newDepositFee;
    }
    struct ProposalDecreaseLeaks {
        bool valid;
        uint256 farmMultiplier;
        uint256 memeMultiplier;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
        uint256 firstCallTimestamp;
    }
     struct ProposalGovTransfer {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 proposedValue;
		uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
		bool isBurn; //if burn, burns tokens. Else transfers into treasury
		uint256 startTimestamp; //can schedule in advance when they are burned
    }
	
	//burns from old masterchef
   struct ProposalBurn {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 proposedValue;
		uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
		uint256 startTimestamp; //can schedule in advance when they are burned
    }
	
   struct ProposalTax {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 proposedValue;
		uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
    }
	
    ProposalBurn[] public burnProposals; 
    ProposalFarm[] public proposalFarmUpdate;
    ProposalDecreaseLeaks[] public proposeRewardReduction;
	ProposalGovTransfer[] public governorTransferProposals; 
	ProposalTax[] public govTaxProposals; 
    
    address public immutable token; //XVMC token(address!)
	
	address public masterchef;
	
	address public oldChef = 0x9BD741F077241b594EBdD745945B577d59C8768e;
    
    uint256 maxRewards = 26000 * 1e18; //maximum reward/block when boosts inactivated
    
    //farms and meme pools rewards have no lock 
    //reduce the rewards during inflation boost
    //to prevent tokens reaching the market
    uint256 public farmMultiplierDuringBoost = 500;
    uint256 public memeMultiplierDuringBoost = 500;
    bool public isReductionEnforced; 
    
    event InitiateFarmProposal(
            uint256 proposalID, uint256 depositingTokens, uint256 poolid,
            uint256 newAllocation, uint16 depositFee, address indexed enforcer, uint256 delay
        );
    
    //reward reduction for farms and meme pools during reward boosts
    event ProposeRewardReduction(address enforcer, uint256 proposalID, uint256 farmMultiplier, uint256 memeMultiplier, uint256 depositingTokens, uint256 delay);
	
    event ProposeGovernorTransfer(uint256 proposalID, uint256 valueSacrificedForVote, uint256 proposedAmount, address indexed enforcer, bool isBurn, uint256 startTimestamp, uint256 delay);
	
    event ProposeBurn(uint256 proposalID, uint256 valueSacrificedForVote, uint256 proposedBurn, address indexed enforcer, uint256 startTimestamp, uint256 delay);
	
	event ProposeGovTax(uint256 proposalID, uint256 valueSacrificedForVote, uint256 proposedTax, address indexed enforcer, uint256 delay);
	
	event AddVotes(uint256 _type, uint256 proposalID, address indexed voter, uint256 tokensSacrificed, bool _for);
	event EnforceProposal(uint256 _type, uint256 proposalID, address indexed enforcer, bool isSuccess);
    
	constructor (address _XVMC, address _masterchef)  {
		token = _XVMC;
		masterchef = _masterchef;
	}
    
    /**
     * Regulatory process to regulate farm rewards 
     * And Meme pools
    */    
    function initiateFarmProposal(
            uint256 depositingTokens, uint256 poolid, uint256 newAllocation, uint16 depositFee, uint256 delay
        ) external { 
    	require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
    	require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "there is a minimum cost to vote");
    	require(poolid == 0 || poolid == 1 || poolid == 8 || poolid == 9 || poolid == 10, "only allowed for these pools"); 
		
		//0 and 1 are XVMC-USDC and XVMC-wMatic pools
		//7 and 8 are meme pools
		//9 is for NFT staking(nfts and virtual land)
    	if(poolid == 0 || poolid == 1) {
    	    require(
    	        newAllocation <= (IMasterChef(masterchef).totalAllocPoint() * 125 / 1000),
    	        "Maximum 12.5% of total allocation"
    	       );
    	} else if(poolid == 10) {
			require(
    	        newAllocation <= (IMasterChef(masterchef).totalAllocPoint() * 2 / 10),
    	        "Maximum 20% of total allocation"
    	       );
			require(depositFee == 0, "deposit fee must be 0 for NFTs");
		} else {
    	    require(
    	        newAllocation <= (IMasterChef(masterchef).totalAllocPoint() * 5 / 100),
    	        "Maximum 5% of total allocation"
    	       ); 
    	}
    
    	IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens); 
    	proposalFarmUpdate.push(
    	    ProposalFarm(true, poolid, newAllocation, depositingTokens, 0, delay, block.timestamp, depositFee)
    	    ); 
    	emit InitiateFarmProposal(proposalFarmUpdate.length - 1, depositingTokens, poolid, newAllocation, depositFee, msg.sender, delay);
    }
	function voteFarmProposalY(uint256 proposalID, uint256 withTokens) external {
		require(proposalFarmUpdate[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		proposalFarmUpdate[proposalID].valueSacrificedForVote+= withTokens;
			
		emit AddVotes(0, proposalID, msg.sender, withTokens, true);
	}
	function voteFarmProposalN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(proposalFarmUpdate[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);
		
		proposalFarmUpdate[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoFarmProposal(proposalID); }

		emit AddVotes(0, proposalID, msg.sender, withTokens, false);
	}
    function vetoFarmProposal(uint256 proposalID) public {
    	require(proposalFarmUpdate[proposalID].valid, "already invalid");
		require(proposalFarmUpdate[proposalID].firstCallTimestamp + proposalFarmUpdate[proposalID].delay <= block.timestamp, "pending delay");
		require(proposalFarmUpdate[proposalID].valueSacrificedForVote < proposalFarmUpdate[proposalID].valueSacrificedAgainst, "needs more votes");
		
    	proposalFarmUpdate[proposalID].valid = false; 
    	
    	emit EnforceProposal(0, proposalID, msg.sender, false);
    }
    
    /**
     * Updates the rewards for the corresponding farm in the proposal
    */
    function updateFarm(uint256 proposalID) public {
        require(!isReductionEnforced, "reward reduction is active"); //only when reduction is not enforced
        require(proposalFarmUpdate[proposalID].valid, "invalid proposal");
        require(
            proposalFarmUpdate[proposalID].firstCallTimestamp + IXVMCgovernor(owner()).delayBeforeEnforce() + proposalFarmUpdate[proposalID].delay  < block.timestamp,
            "delay before enforce not met"
            );
        
		if(proposalFarmUpdate[proposalID].valueSacrificedForVote >= proposalFarmUpdate[proposalID].valueSacrificedAgainst) {
			IXVMCgovernor(owner()).setPool(proposalFarmUpdate[proposalID].poolid, proposalFarmUpdate[proposalID].newAllocation, proposalFarmUpdate[proposalID].newDepositFee, true);
			proposalFarmUpdate[proposalID].valid = false;
			
			emit EnforceProposal(0, proposalID, msg.sender, true);
		} else {
			vetoFarmProposal(proposalID);
		}
    }

    /**
     * Regulatory process for determining rewards for 
     * farms and meme pools during inflation boosts
     * The rewards should be reduced for farms and pool tha toperate without time lock
     * to prevent tokens from hitting the market
    */
    function initiateRewardsReduction(uint256 depositingTokens, uint256 multiplierFarms, uint256 multiplierMemePools, uint256 delay) external {
    	require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "minimum cost to vote");
		require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
		require(multiplierFarms <= 10000 && multiplierMemePools <= 10000, "out of range");
    	
		IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens); 
		    proposeRewardReduction.push(
		        ProposalDecreaseLeaks(true, multiplierFarms, multiplierMemePools, depositingTokens, 0, delay, block.timestamp)
		        );
    	
    	emit ProposeRewardReduction(msg.sender, proposeRewardReduction.length - 1, multiplierFarms, multiplierMemePools, depositingTokens, delay);
    }
	function voteRewardsReductionY(uint256 proposalID, uint256 withTokens) external {
		require(proposeRewardReduction[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		proposeRewardReduction[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(1, proposalID, msg.sender, withTokens, true);
	}
	function voteRewardsReductionN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(proposeRewardReduction[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		proposeRewardReduction[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoRewardsReduction(proposalID); }

		emit AddVotes(1, proposalID, msg.sender, withTokens, false);
	}
    function vetoRewardsReduction(uint256 proposalID) public {
    	require(proposeRewardReduction[proposalID].valid == true, "Proposal already invalid");
		require(proposeRewardReduction[proposalID].firstCallTimestamp + proposeRewardReduction[proposalID].delay <= block.timestamp, "pending delay");
		require(proposeRewardReduction[proposalID].valueSacrificedForVote < proposeRewardReduction[proposalID].valueSacrificedAgainst, "needs more votes");
		
    	proposeRewardReduction[proposalID].valid = false;  
    	
    	emit EnforceProposal(1, proposalID, msg.sender, false);
    }
    function executeRewardsReduction(uint256 proposalID) public {
		require(!isReductionEnforced, "reward reduction is active"); //only when reduction is not enforced
    	require(
    	    proposeRewardReduction[proposalID].valid &&
    	    proposeRewardReduction[proposalID].firstCallTimestamp + IXVMCgovernor(owner()).delayBeforeEnforce() + proposeRewardReduction[proposalID].delay < block.timestamp,
    	    "Conditions not met"
    	   );
		   
		if(proposeRewardReduction[proposalID].valueSacrificedForVote >= proposeRewardReduction[proposalID].valueSacrificedAgainst) {
			farmMultiplierDuringBoost = proposeRewardReduction[proposalID].farmMultiplier;
			memeMultiplierDuringBoost = proposeRewardReduction[proposalID].memeMultiplier;
			proposeRewardReduction[proposalID].valid = false;
			
			emit EnforceProposal(1, proposalID, msg.sender, true);
		} else {
			vetoRewardsReduction(proposalID);
		}
    }
    
    /**
     * When event is active, reduction of rewards must be manually activated
     * Reduces the rewards by a factor
     * Call this to enforce and "un-enforce"
    */
    function enforceRewardReduction(bool withUpdate) public {
        uint256 allocPoint; uint16 depositFeeBP;
        if (IXVMCgovernor(owner()).eventFibonacceningActive() && !isReductionEnforced) {
            
            (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(0);
            IXVMCgovernor(owner()).setPool(
                0, allocPoint * farmMultiplierDuringBoost / 10000, depositFeeBP, false
            );
            
            (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(1);
            IXVMCgovernor(owner()).setPool(
                1, allocPoint * farmMultiplierDuringBoost / 10000, depositFeeBP, false
            );

            (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(8);
            IXVMCgovernor(owner()).setPool(
                7, allocPoint * memeMultiplierDuringBoost / 10000, depositFeeBP, false
            );

            (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(9);
            IXVMCgovernor(owner()).setPool(
                8, allocPoint * memeMultiplierDuringBoost / 10000, depositFeeBP, false
            );
            
            isReductionEnforced = true;
            
        } else if(!(IXVMCgovernor(owner()).eventFibonacceningActive()) && isReductionEnforced) {

        //inverses the formula... perhaps should keep last Reward
        //the mutliplier shall not change during event!
            (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(0);
            IXVMCgovernor(owner()).setPool(
                0, allocPoint * 10000 / farmMultiplierDuringBoost, depositFeeBP, false
            );
            
            (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(1);
            IXVMCgovernor(owner()).setPool(
                1, allocPoint * 10000 / farmMultiplierDuringBoost, depositFeeBP, false
            );

            (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(8);
            IXVMCgovernor(owner()).setPool(
                7, allocPoint * 10000 / memeMultiplierDuringBoost, depositFeeBP, false
            );

            (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(9);
            IXVMCgovernor(owner()).setPool(
                8, allocPoint * 10000 / memeMultiplierDuringBoost, depositFeeBP, false
            );
            
            isReductionEnforced = false;
        }
	
	if(withUpdate) { updateAllPools(); }
    }

	//updates all pools in masterchef
    function updateAllPools() public {
        IMasterChef(IToken(token).owner()).massUpdate();
    }

	/*
	* Transfer tokens from governor into treasury wallet OR burn them from governor
	* alternatively could change devaddr to the treasury wallet in masterchef(portion of inflation goes to devaddr)
	*/
  function proposeGovernorTransfer(uint256 depositingTokens, uint256 _amount, bool _isBurn, uint256 _timestamp, uint256 delay) external {
        require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "Costs to vote");
        require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
		require(_amount <= IERC20(token).balanceOf(owner()), "insufficient balance");
        
    	IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens);
    	governorTransferProposals.push(
    	    ProposalGovTransfer(true, block.timestamp, _amount, depositingTokens, 0, delay, _isBurn, _timestamp)
    	    );
		
    	emit ProposeGovernorTransfer(
    	    governorTransferProposals.length - 1, depositingTokens, _amount, msg.sender, _isBurn, _timestamp, delay
    	   );
    }
	function voteGovernorTransferY(uint256 proposalID, uint256 withTokens) external {
		require(governorTransferProposals[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		governorTransferProposals[proposalID].valueSacrificedForVote+= withTokens;
			
		emit AddVotes(2, proposalID, msg.sender, withTokens, true);
	}
	function voteGovernorTransferN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(governorTransferProposals[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);
		
		governorTransferProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoGovernorTransfer(proposalID); }

		emit AddVotes(2, proposalID, msg.sender, withTokens, false);
	}
    function vetoGovernorTransfer(uint256 proposalID) public {
    	require(governorTransferProposals[proposalID].valid == true, "Invalid proposal"); 
		require(governorTransferProposals[proposalID].firstCallTimestamp + governorTransferProposals[proposalID].delay <= block.timestamp, "pending delay");
		require(governorTransferProposals[proposalID].valueSacrificedForVote < governorTransferProposals[proposalID].valueSacrificedAgainst, "needs more votes");
		
    	governorTransferProposals[proposalID].valid = false;

		emit EnforceProposal(2, proposalID, msg.sender, false);
    }
    function executeGovernorTransfer(uint256 proposalID) public {
    	require(
    	    governorTransferProposals[proposalID].valid == true &&
    	    governorTransferProposals[proposalID].firstCallTimestamp + IXVMCgovernor(owner()).delayBeforeEnforce() + governorTransferProposals[proposalID].delay  < block.timestamp,
    	    "conditions not met"
        );
		require(governorTransferProposals[proposalID].startTimestamp < block.timestamp, "Not yet eligible");
    	
		if(governorTransferProposals[proposalID].valueSacrificedForVote >= governorTransferProposals[proposalID].valueSacrificedAgainst) {
			if(governorTransferProposals[proposalID].isBurn) {
				IERC20(token).burnXVMC(owner(), governorTransferProposals[proposalID].proposedValue);
			} else {
				IERC20(token).safeTransferFrom(owner(), IXVMCgovernor(owner()).treasuryWallet(), governorTransferProposals[proposalID].proposedValue);
			}

			governorTransferProposals[proposalID].valid = false; 
			
			emit EnforceProposal(2, proposalID, msg.sender, true);
		} else {
			vetoGovernorTransfer(proposalID);
		}
    }
	
	//in case masterchef is changed
   function setMasterchef() external {
		address _chefo = IMasterChef(token).owner();
		
        masterchef = _chefo;
    }
   
    //transfers ownership of this contract to new governor
    //masterchef is the token owner, governor is the owner of masterchef
    function changeGovernor() external {
		_transferOwnership(IToken(token).governor());
    }
	
	//burn from old masterchef
	// 0 as proposed value will burn all the tokens held by contract
  function proposeBurn(uint256 depositingTokens, uint256 _amount, uint256 _timestamp, uint256 delay) external {
        require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "Costs to vote");
        require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
		require(_amount <= IERC20(token).balanceOf(IMasterChef(oldChef).owner()), "insufficient balance");
        
    	IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens);
    	burnProposals.push(
    	    ProposalBurn(true, block.timestamp, _amount, depositingTokens, 0, delay, _timestamp)
    	    );
		
    	emit ProposeBurn(
    	    burnProposals.length - 1, depositingTokens, _amount, msg.sender, _timestamp, delay
    	   );
    }
	function voteBurnY(uint256 proposalID, uint256 withTokens) external {
		require(burnProposals[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		burnProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(3, proposalID, msg.sender, withTokens, true);
	}
	function voteBurnN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(burnProposals[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);
		
		burnProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoBurn(proposalID); }

		emit AddVotes(3, proposalID, msg.sender, withTokens, false);
	}
    function vetoBurn(uint256 proposalID) public {
    	require(burnProposals[proposalID].valid == true, "Invalid proposal");
		require(burnProposals[proposalID].firstCallTimestamp + burnProposals[proposalID].delay <= block.timestamp, "pending delay");
		require(burnProposals[proposalID].valueSacrificedForVote < burnProposals[proposalID].valueSacrificedAgainst, "needs more votes");
		
    	burnProposals[proposalID].valid = false;
    	
    	emit EnforceProposal(3, proposalID, msg.sender, false);
    }
    function executeBurn(uint256 proposalID) public {
    	require(
    	    burnProposals[proposalID].valid == true &&
    	    burnProposals[proposalID].firstCallTimestamp + IOldChefOwner(IMasterChef(oldChef).owner()).burnDelay() + burnProposals[proposalID].delay  < block.timestamp,
    	    "conditions not met"
        );
    	require(burnProposals[proposalID].startTimestamp <= block.timestamp, "Not yet eligible");
		
		if(burnProposals[proposalID].valueSacrificedForVote >= burnProposals[proposalID].valueSacrificedAgainst) {
			IXVMCgovernor(owner()).burnFromOldChef(burnProposals[proposalID].proposedValue); //burns the tokens
			burnProposals[proposalID].valid = false; 
			
			emit EnforceProposal(3, proposalID, msg.sender, true);
		} else {
			vetoBurn(proposalID);
		}
    }
	
	//Proposals to set governor 'tax'(in masterchef, on every mint this % of inflation goes to the governor)
	//1000 = 10%. Max 10%
	// ( mintTokens * thisAmount / 10 000 ) in the masterchef contract
  function proposeGovTax(uint256 depositingTokens, uint256 _amount, uint256 delay) external {
        require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "Costs to vote");
        require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
		require(_amount <= 1000 && _amount > 0, "max 1000");
        
    	IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens);
    	govTaxProposals.push(
    	    ProposalTax(true, block.timestamp, _amount, depositingTokens, 0, delay)
    	    );
		
    	emit ProposeGovTax(
    	    govTaxProposals.length - 1, depositingTokens, _amount, msg.sender, delay
    	   );
    }
	function voteGovTaxY(uint256 proposalID, uint256 withTokens) external {
		require(govTaxProposals[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		govTaxProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(4, proposalID, msg.sender, withTokens, true);
	}
	function voteGovTaxN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(govTaxProposals[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);
		
		govTaxProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoGovTax(proposalID); }

		emit AddVotes(4, proposalID, msg.sender, withTokens, false);
	}
    function vetoGovTax(uint256 proposalID) public {
    	require(govTaxProposals[proposalID].valid == true, "Invalid proposal");
		require(govTaxProposals[proposalID].firstCallTimestamp + govTaxProposals[proposalID].delay <= block.timestamp, "pending delay");
		require(govTaxProposals[proposalID].valueSacrificedForVote < govTaxProposals[proposalID].valueSacrificedAgainst, "needs more votes");
		
    	govTaxProposals[proposalID].valid = false;
    	
    	emit EnforceProposal(4, proposalID, msg.sender, false);
    }
    function executeGovTax(uint256 proposalID) public {
    	require(
    	    govTaxProposals[proposalID].valid == true &&
    	    govTaxProposals[proposalID].firstCallTimestamp + IXVMCgovernor(owner()).delayBeforeEnforce() + govTaxProposals[proposalID].delay  < block.timestamp,
    	    "conditions not met"
        );
		
		if(govTaxProposals[proposalID].valueSacrificedForVote >= govTaxProposals[proposalID].valueSacrificedAgainst) {
			IXVMCgovernor(owner()).setGovernorTax(govTaxProposals[proposalID].proposedValue); //burns the tokens
			govTaxProposals[proposalID].valid = false; 
			
			emit EnforceProposal(4, proposalID, msg.sender, true);
		} else {
			vetoGovTax(proposalID);
		}
    }
}
