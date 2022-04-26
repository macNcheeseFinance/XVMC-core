// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libs/custom/IERC20.sol";
import "./libs/standard/Address.sol";
import "./libs/custom/SafeERC20.sol";

interface IXVMCgovernor {
    function costToVote() external returns (uint256);
    function updateCostToVote(uint256 newCostToVote) external;
    function updateDelayBeforeEnforce(uint256 newDelay) external; 
    function delayBeforeEnforce() external returns (uint256);
    function updateDurationForCalculation(uint256 newDuration) external;
    function setCallFee(address acPool, uint256 newCallFee) external;
    function changeGovernorEnforced() external returns (bool);
    function eligibleNewGovernor() external returns (address);
	function updateRolloverBonus(address _forPool, uint256 bonus) external;
    function acPool1() external view returns (address);
    function acPool2() external view returns (address);
    function acPool3() external view returns (address);
    function acPool4() external view returns (address);
    function acPool5() external view returns (address);
    function acPool6() external view returns (address);
	function maximumVoteTokens() external view returns (uint256);
	function getTotalSupply() external view returns (uint256);
    function setThresholdFibonaccening(uint256 newThreshold) external;
    function updateGrandEventLength(uint256 _amount) external;
    function updateDelayBetweenEvents(uint256 _amount) external;
}

interface IToken {
    function governor() external view returns (address);
}

//compile with optimization enabled(60runs)
contract XVMCbasics is Ownable {
    using SafeERC20 for IERC20;

    address public immutable token; //XVMC token (address)
    
    //addresses for time-locked deposits(autocompounding pools)
    address public acPool1;
    address public acPool2;
    address public acPool3;
    address public acPool4;
    address public acPool5;
    address public acPool6;
    
    struct ProposalStructure {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay; //delay is basically time before users can vote against the proposal
        uint256 proposedValue;
    }
    struct RolloverBonusStructure {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
        address poolAddress;
        uint256 newBonus;
    }
    struct ParameterStructure {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay; //delay is basically time before users can vote against the proposal
        uint256 proposedValue1; // delay between events
        uint256 proposedValue2; // duration when the print happens
    }
    
    ProposalStructure[] public minDepositProposals;
    ProposalStructure[] public delayProposals;
    ProposalStructure[] public proposeDurationCalculation;
	ProposalStructure[] public callFeeProposal;
	RolloverBonusStructure[] public rolloverBonuses;
	ProposalStructure[] public minThresholdFibonacceningProposal; 
    ParameterStructure[] public grandSettingProposal;
	
	event ProposeMinDeposit(uint256 proposalID, uint256 valueSacrificedForVote, uint256 proposedMinDeposit, address enforcer, uint256 delay);
    
    event DelayBeforeEnforce(uint256 proposalID, uint256 valueSacrificedForVote, uint256 proposedMinDeposit, address enforcer, uint256 delay);
    
    event InitiateProposalDurationForCalculation(uint256 proposalID, uint256 duration, uint256 tokensSacrificedForVoting, address enforcer, uint256 delay);
    
    event InitiateSetCallFee(uint256 proposalID, uint256 depositingTokens, uint256 newCallFee, address enforcer, uint256 delay);
    
    event InitiateRolloverBonus(uint256 proposalID, uint256 depositingTokens, address forPool, uint256 newBonus, address enforcer, uint256 delay);
	
	event ProposeSetMinThresholdFibonaccening(uint256 proposalID, uint256 valueSacrificedForVote, uint256 proposedMinDeposit, address indexed enforcer, uint256 delay);

    event ProposeSetGrandParameters(uint256 proposalID, uint256 valueSacrificedForVote, address indexed enforcer, uint256 delay, uint256 delayBetween, uint256 duration);
    
	
	event AddVotes(uint256 _type, uint256 proposalID, address indexed voter, uint256 tokensSacrificed, bool _for);
	event EnforceProposal(uint256 _type, uint256 proposalID, address indexed enforcer, bool isSuccess);

    event ChangeGovernor(address newGovernor);
    
	constructor(address _XVMC) {
		token = _XVMC;
	}
    
    /**
     * Regulatory process for determining "IXVMCgovernor(owner()).IXVMCgovernor(owner()).costToVote()()"
     * Anyone should be able to cast a vote
     * Since all votes are deemed valid, unless rejected
     * All votes must be manually reviewed
     * minimum IXVMCgovernor(owner()).costToVote() prevents spam
	 * Delay is the time during which you can vote in favor of the proposal(but can't veto/cancle it)
	 * Proposal is submitted. During delay you can vote FOR the proposal. After delay expires the proposal
	 * ... can be cancled(veto'd) if more tokens are commited against than in favor
	 * If not cancled, the proposal can be enforced after (delay + delayBeforeEnforce) expires
	 * ...under condition that more tokens have been sacrificed in favor rather than against
    */
    function initiateSetMinDeposit(uint256 depositingTokens, uint256 newMinDeposit, uint256 delay) external {
		require(newMinDeposit <= IXVMCgovernor(owner()).maximumVoteTokens(), 'Maximum 0.01% of all tokens');
		require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
    	
    	if (newMinDeposit < IXVMCgovernor(owner()).costToVote()) {
    		require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "Minimum cost to vote not met");
    		IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens);
    	} else {
    		require(depositingTokens >= newMinDeposit, "Must match new amount");
    		IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens); 
    	}
		
		minDepositProposals.push(
    		        ProposalStructure(true, block.timestamp, depositingTokens, 0, delay, newMinDeposit)
    		   ); 
    	
    	emit ProposeMinDeposit(minDepositProposals.length - 1, depositingTokens, newMinDeposit, msg.sender, delay);
    }
	function voteSetMinDepositY(uint256 proposalID, uint256 withTokens) external {
		require(minDepositProposals[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);
		
		minDepositProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(0, proposalID, msg.sender, withTokens, true);
	}
	function voteSetMinDepositN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(minDepositProposals[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);
		
		minDepositProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoSetMinDeposit(proposalID); }

		emit AddVotes(0, proposalID, msg.sender, withTokens, false);
	}
    function vetoSetMinDeposit(uint256 proposalID) public {
    	require(minDepositProposals[proposalID].valid == true, "Proposal already invalid");
		require(minDepositProposals[proposalID].firstCallTimestamp + minDepositProposals[proposalID].delay < block.timestamp, "pending delay");
		require(minDepositProposals[proposalID].valueSacrificedForVote < minDepositProposals[proposalID].valueSacrificedAgainst, "needs more votes");

    	minDepositProposals[proposalID].valid = false;  
    	
    	emit EnforceProposal(0, proposalID, msg.sender, false);
    }
    function executeSetMinDeposit(uint256 proposalID) public {
    	require(
    	    minDepositProposals[proposalID].valid &&
    	    minDepositProposals[proposalID].firstCallTimestamp + minDepositProposals[proposalID].delay + IXVMCgovernor(owner()).delayBeforeEnforce() <= block.timestamp,
    	    "Conditions not met"
    	   );
		   
		 if(minDepositProposals[proposalID].valueSacrificedForVote >= minDepositProposals[proposalID].valueSacrificedAgainst) {
			IXVMCgovernor(owner()).updateCostToVote(minDepositProposals[proposalID].proposedValue); 
			minDepositProposals[proposalID].valid = false;
			
			emit EnforceProposal(0, proposalID, msg.sender, true);
		 } else {
			 vetoSetMinDeposit(proposalID);
		 }
    }

    
    /**
     * Regulatory process for determining "delayBeforeEnforce"
     * After a proposal is initiated, a period of time called
     * delayBeforeEnforce must pass, before the proposal can be enforced
     * During this period proposals can be vetod(voted against = rejected)
    */
    function initiateDelayBeforeEnforceProposal(uint256 depositingTokens, uint256 newDelay, uint256 delay) external { 
    	require(newDelay >= 1 days && newDelay <= 14 days && delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "Minimum 1 day");
    	
    	IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens);
    	delayProposals.push(
    	    ProposalStructure(true, block.timestamp, depositingTokens, 0, delay, newDelay)
    	   );  
		   
        emit DelayBeforeEnforce(delayProposals.length - 1, depositingTokens, newDelay, msg.sender, delay);
    }
	function voteDelayBeforeEnforceProposalY(uint256 proposalID, uint256 withTokens) external {
		require(delayProposals[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		delayProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(1, proposalID, msg.sender, withTokens, true);
	}
	function voteDelayBeforeEnforceProposalN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(delayProposals[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);
		
		delayProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoDelayBeforeEnforceProposal(proposalID); }

		emit AddVotes(1, proposalID, msg.sender, withTokens, false);
	}
    function vetoDelayBeforeEnforceProposal(uint256 proposalID) public {
    	require(delayProposals[proposalID].valid == true, "Proposal already invalid");
		require(delayProposals[proposalID].firstCallTimestamp + delayProposals[proposalID].delay < block.timestamp, "pending delay");
		require(delayProposals[proposalID].valueSacrificedForVote < delayProposals[proposalID].valueSacrificedAgainst, "needs more votes");
    	
    	delayProposals[proposalID].valid = false;  
		
    	emit EnforceProposal(1, proposalID, msg.sender, false);
    }
    function executeDelayBeforeEnforceProposal(uint256 proposalID) public {
    	require(
    	    delayProposals[proposalID].valid == true &&
    	    delayProposals[proposalID].firstCallTimestamp + IXVMCgovernor(owner()).delayBeforeEnforce() + delayProposals[proposalID].delay < block.timestamp,
    	    "Conditions not met"
    	    );
        
		if(delayProposals[proposalID].valueSacrificedForVote >= delayProposals[proposalID].valueSacrificedAgainst) {
			IXVMCgovernor(owner()).updateDelayBeforeEnforce(delayProposals[proposalID].proposedValue); 
			delayProposals[proposalID].valid = false;
			
			emit EnforceProposal(1, proposalID, msg.sender, true);
		} else {
			vetoDelayBeforeEnforceProposal(proposalID);
		}
    }
    
  /**
     * Regulatory process for determining "durationForCalculation"
     * Not of great Use (no use until the "grand fibonaccening
     * Bitcoin difficulty adjusts to create new blocks every 10minutes
     * Our inflation is tied to the block production of Polygon network
     * In case the average block time changes significantly on the Polygon network  
     * the durationForCalculation is a period that we use to calculate 
     * average block time and consequentially use it to rebalance inflation
    */
    function initiateProposalDurationForCalculation(uint256 depositingTokens, uint256 duration, uint256 delay) external {
		require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");		
    	require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "minimum cost to vote");
		require(duration <= 7 * 24 * 3600, "less than 7 days");
    
    	IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens);
    	proposeDurationCalculation.push(
    	    ProposalStructure(true, block.timestamp, depositingTokens, 0, delay, duration)
    	    );  
    	    
        emit InitiateProposalDurationForCalculation(proposeDurationCalculation.length - 1, duration,  depositingTokens, msg.sender, delay);
    }
	function voteProposalDurationForCalculationY(uint256 proposalID, uint256 withTokens) external {
		require(proposeDurationCalculation[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		proposeDurationCalculation[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(2, proposalID, msg.sender, withTokens, true);
	}
	function voteProposalDurationForCalculationN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(proposeDurationCalculation[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		proposeDurationCalculation[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoProposalDurationForCalculation(proposalID); }

		emit AddVotes(2, proposalID, msg.sender, withTokens, false);
	}
    function vetoProposalDurationForCalculation(uint256 proposalID) public {
    	require(proposeDurationCalculation[proposalID].valid, "already invalid"); 
		require(proposeDurationCalculation[proposalID].firstCallTimestamp + proposeDurationCalculation[proposalID].delay < block.timestamp, "pending delay");
		require(proposeDurationCalculation[proposalID].valueSacrificedForVote < proposeDurationCalculation[proposalID].valueSacrificedAgainst, "needs more votes");

    	proposeDurationCalculation[proposalID].valid = false;  
    	
    	emit EnforceProposal(2, proposalID, msg.sender, false);
    }

    function executeProposalDurationForCalculation(uint256 proposalID) public {
    	require(
    	    proposeDurationCalculation[proposalID].valid &&
    	    proposeDurationCalculation[proposalID].firstCallTimestamp + IXVMCgovernor(owner()).delayBeforeEnforce() + proposeDurationCalculation[proposalID].delay < block.timestamp,
    	    "conditions not met"
    	);
		if(proposeDurationCalculation[proposalID].valueSacrificedForVote >= proposeDurationCalculation[proposalID].valueSacrificedAgainst) {
			IXVMCgovernor(owner()).updateDurationForCalculation(proposeDurationCalculation[proposalID].proposedValue); 
			proposeDurationCalculation[proposalID].valid = false; 
			
			emit EnforceProposal(2, proposalID, msg.sender, true);
		} else {
			vetoProposalDurationForCalculation(proposalID);
		}
    }
    
  /**
     * Regulatory process for setting rollover bonuses
    */
    function initiateProposalRolloverBonus(uint256 depositingTokens, address _forPoolAddress, uint256 _newBonus, uint256 delay) external { 
		require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
    	require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "minimum cost to vote");
		require(_newBonus <= 2000, "bonus too high");
    
    	IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens);
    	rolloverBonuses.push(
    	    RolloverBonusStructure(true, block.timestamp, depositingTokens, 0, delay, _forPoolAddress, _newBonus)
    	    );  
    	    
        emit InitiateRolloverBonus(rolloverBonuses.length - 1, depositingTokens, _forPoolAddress, _newBonus, msg.sender, delay);
    }
	function voteProposalRolloverBonusY(uint256 proposalID, uint256 withTokens) external {
		require(rolloverBonuses[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		rolloverBonuses[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(3, proposalID, msg.sender, withTokens, true);
	}
	function voteProposalRolloverBonusN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(rolloverBonuses[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		rolloverBonuses[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoProposalRolloverBonus(proposalID); }

		emit AddVotes(3, proposalID, msg.sender, withTokens, false);
	}
    function vetoProposalRolloverBonus(uint256 proposalID) public {
    	require(rolloverBonuses[proposalID].valid, "already invalid"); 
		require(rolloverBonuses[proposalID].firstCallTimestamp + rolloverBonuses[proposalID].delay < block.timestamp, "pending delay");
		require(rolloverBonuses[proposalID].valueSacrificedForVote < rolloverBonuses[proposalID].valueSacrificedAgainst, "needs more votes");
 
    	rolloverBonuses[proposalID].valid = false;  
    	
    	emit EnforceProposal(3, proposalID, msg.sender, false);
    }

    function executeProposalRolloverBonus(uint256 proposalID) public {
    	require(
    	    rolloverBonuses[proposalID].valid &&
    	    rolloverBonuses[proposalID].firstCallTimestamp + IXVMCgovernor(owner()).delayBeforeEnforce() + rolloverBonuses[proposalID].delay < block.timestamp,
    	    "conditions not met"
    	);
        
		if(rolloverBonuses[proposalID].valueSacrificedForVote >= rolloverBonuses[proposalID].valueSacrificedAgainst) {
			IXVMCgovernor(owner()).updateRolloverBonus(rolloverBonuses[proposalID].poolAddress, rolloverBonuses[proposalID].newBonus); 
			rolloverBonuses[proposalID].valid = false; 
			
			emit EnforceProposal(3, proposalID, msg.sender, true);
		} else {
			vetoProposalRolloverBonus(proposalID);
		}
    }
    
    
	 /**
     * The auto-compounding effect is achieved with the help of the users that initiate the
     * transaction and pay the gas fee for re-investing earnings into the Masterchef
     * The call fee is paid as a reward to the user
     * This is handled in the auto-compounding contract
     * 
     * This is a process to change the Call fee(the reward) in the autocompounding contracts
     * This contract is an admin for the autocompound contract
     */
    function initiateSetCallFee(uint256 depositingTokens, uint256 newCallFee, uint256 delay) external { 
    	require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "below minimum cost to vote");
    	require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
    	require(newCallFee <= 1000);
    
    	IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens);
    	callFeeProposal.push(
    	    ProposalStructure(true, block.timestamp, depositingTokens, 0, delay, newCallFee)
    	   );
    	   
        emit InitiateSetCallFee(callFeeProposal.length - 1, depositingTokens, newCallFee, msg.sender, delay);
    }
	function voteSetCallFeeY(uint256 proposalID, uint256 withTokens) external {
		require(callFeeProposal[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		callFeeProposal[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(4, proposalID, msg.sender, withTokens, true);
	}
	function voteSetCallFeeN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(callFeeProposal[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);
		
		callFeeProposal[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoSetCallFee(proposalID); }

		emit AddVotes(4, proposalID, msg.sender, withTokens, false);
	}
    function vetoSetCallFee(uint256 proposalID) public {
    	require(callFeeProposal[proposalID].valid == true, "Proposal already invalid");
		require(callFeeProposal[proposalID].firstCallTimestamp + callFeeProposal[proposalID].delay < block.timestamp, "pending delay");
		require(callFeeProposal[proposalID].valueSacrificedForVote < callFeeProposal[proposalID].valueSacrificedAgainst, "needs more votes");

    	callFeeProposal[proposalID].valid = false;
    	
    	emit EnforceProposal(4, proposalID, msg.sender, false);
    }
    function executeSetCallFee(uint256 proposalID) public {
    	require(
    	    callFeeProposal[proposalID].valid && 
    	    callFeeProposal[proposalID].firstCallTimestamp + IXVMCgovernor(owner()).delayBeforeEnforce() + callFeeProposal[proposalID].delay < block.timestamp,
    	    "Conditions not met"
    	   );
        
		if(callFeeProposal[proposalID].valueSacrificedForVote >= callFeeProposal[proposalID].valueSacrificedAgainst) {

			IXVMCgovernor(owner()).setCallFee(acPool1, callFeeProposal[proposalID].proposedValue);
			IXVMCgovernor(owner()).setCallFee(acPool2, callFeeProposal[proposalID].proposedValue);
			IXVMCgovernor(owner()).setCallFee(acPool3, callFeeProposal[proposalID].proposedValue);
			IXVMCgovernor(owner()).setCallFee(acPool4, callFeeProposal[proposalID].proposedValue);
			IXVMCgovernor(owner()).setCallFee(acPool5, callFeeProposal[proposalID].proposedValue);
			IXVMCgovernor(owner()).setCallFee(acPool6, callFeeProposal[proposalID].proposedValue);
			
			callFeeProposal[proposalID].valid = false;
			
			emit EnforceProposal(4, proposalID, msg.sender, true);
		} else {
			vetoSetCallFee(proposalID);
		}
    }
	
    /**
     * Regulatory process for determining fibonaccening threshold,
     * which is the minimum amount of tokens required to be collected,
     * before a "fibonaccening" event can be scheduled;
     * 
     * Bitcoin has "halvening" events every 4 years where block rewards reduce in half
     * XVMC has "fibonaccening" events, which can can be scheduled once
     * this smart contract collects the minimum(threshold) of tokens. 
     * 
     * Tokens are collected as penalties from premature withdrawals, as well as voting costs inside this contract
     *
     * It's basically a mechanism to re-distribute the penalties(though the rewards can exceed the collected penalties)
     * 
     * It's meant to serve as a volatility-inducing event that attracts new users with high rewards
     * 
     * Effectively, the rewards are increased for a short period of time. 
     * Once the event expires, the tokens collected from penalties are
     * burned to give a sense of deflation AND the global inflation
     * for XVMC is reduced by a Golden ratio
    */
    function proposeSetMinThresholdFibonaccening(uint256 depositingTokens, uint256 newMinimum, uint256 delay) external {
        require(newMinimum >= IXVMCgovernor(owner()).getTotalSupply() / 1000, "Min 0.1% of supply");
        require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "Costs to vote");
        require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
        
    	IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens);
    	minThresholdFibonacceningProposal.push(
    	    ProposalStructure(true, block.timestamp, depositingTokens, 0, delay, newMinimum)
    	    );
		
    	emit ProposeSetMinThresholdFibonaccening(
    	    minThresholdFibonacceningProposal.length - 1, depositingTokens, newMinimum, msg.sender, delay
    	   );
    }
	function voteSetMinThresholdFibonacceningY(uint256 proposalID, uint256 withTokens) external {
		require(minThresholdFibonacceningProposal[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);
		
		minThresholdFibonacceningProposal[proposalID].valueSacrificedForVote+= withTokens;
			
		emit AddVotes(5, proposalID, msg.sender, withTokens, true);
	}
	function voteSetMinThresholdFibonacceningN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(minThresholdFibonacceningProposal[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		minThresholdFibonacceningProposal[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoSetMinThresholdFibonaccening(proposalID); }

		emit AddVotes(5, proposalID, msg.sender, withTokens, false);
	}
    function vetoSetMinThresholdFibonaccening(uint256 proposalID) public {
    	require(minThresholdFibonacceningProposal[proposalID].valid == true, "Invalid proposal"); 
		require(minThresholdFibonacceningProposal[proposalID].firstCallTimestamp + minThresholdFibonacceningProposal[proposalID].delay <= block.timestamp, "pending delay");
		require(minThresholdFibonacceningProposal[proposalID].valueSacrificedForVote < minThresholdFibonacceningProposal[proposalID].valueSacrificedAgainst, "needs more votes");

    	minThresholdFibonacceningProposal[proposalID].valid = false;
    	
    	emit EnforceProposal(5, proposalID, msg.sender, false);
    }
    function executeSetMinThresholdFibonaccening(uint256 proposalID) public {
    	require(
    	    minThresholdFibonacceningProposal[proposalID].valid == true &&
    	    minThresholdFibonacceningProposal[proposalID].firstCallTimestamp + IXVMCgovernor(owner()).delayBeforeEnforce() + minThresholdFibonacceningProposal[proposalID].delay < block.timestamp,
    	    "conditions not met"
        );
    	
		if(minThresholdFibonacceningProposal[proposalID].valueSacrificedForVote >= minThresholdFibonacceningProposal[proposalID].valueSacrificedAgainst) {
			IXVMCgovernor(owner()).setThresholdFibonaccening(minThresholdFibonacceningProposal[proposalID].proposedValue);
			minThresholdFibonacceningProposal[proposalID].valid = false; 
			
			emit EnforceProposal(5, proposalID, msg.sender, true);
		} else {
			vetoSetMinThresholdFibonaccening(proposalID);
		}
    }

    //proposal to set delay between events and duration during which the tokens are printed
    //this is only to be used for "the grand fibonaccening"... Won't happen for some time
    function proposeSetGrandParameters(uint256 depositingTokens, uint256 delay, uint256 _delayBetween, uint256 _duration) external {
        require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "Costs to vote");
        require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
        require(_delayBetween > 24*3600 && _delayBetween <= 7*24*3600, "not within range limits");
        require(_duration > 3600 && _duration < 14*24*3600, "not within range limits");
        
    	IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens);
    	grandSettingProposal.push(
    	    ParameterStructure(true, block.timestamp, depositingTokens, 0, delay, _delayBetween, _duration)
    	    );
		
    	emit ProposeSetGrandParameters(
    	    grandSettingProposal.length - 1, depositingTokens, msg.sender, delay, _delayBetween, _duration
    	   );
    }
	function voteSetGrandParametersY(uint256 proposalID, uint256 withTokens) external {
		require(grandSettingProposal[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);
		
		grandSettingProposal[proposalID].valueSacrificedForVote+= withTokens;
			
		emit AddVotes(6, proposalID, msg.sender, withTokens, true);
	}
	function voteSetGrandParametersN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(grandSettingProposal[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		grandSettingProposal[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoSetGrandParameters(proposalID); }

		emit AddVotes(6, proposalID, msg.sender, withTokens, false);
	}
    function vetoSetGrandParameters(uint256 proposalID) public {
    	require(grandSettingProposal[proposalID].valid == true, "Invalid proposal"); 
		require(grandSettingProposal[proposalID].firstCallTimestamp + grandSettingProposal[proposalID].delay <= block.timestamp, "pending delay");
		require(grandSettingProposal[proposalID].valueSacrificedForVote < grandSettingProposal[proposalID].valueSacrificedAgainst, "needs more votes");

    	grandSettingProposal[proposalID].valid = false;
    	
    	emit EnforceProposal(6, proposalID, msg.sender, false);
    }
    function executeSetGrandParameters(uint256 proposalID) public {
    	require(
    	    grandSettingProposal[proposalID].valid == true &&
    	    grandSettingProposal[proposalID].firstCallTimestamp + IXVMCgovernor(owner()).delayBeforeEnforce() + grandSettingProposal[proposalID].delay < block.timestamp,
    	    "conditions not met"
        );	
    	
		if(grandSettingProposal[proposalID].valueSacrificedForVote >= grandSettingProposal[proposalID].valueSacrificedAgainst) {
			IXVMCgovernor(owner()).updateDelayBetweenEvents(grandSettingProposal[proposalID].proposedValue1); //delay
            IXVMCgovernor(owner()).updateGrandEventLength(grandSettingProposal[proposalID].proposedValue2); //duration
			grandSettingProposal[proposalID].valid = false; 
			
			emit EnforceProposal(6, proposalID, msg.sender, true);
		} else {
			vetoSetGrandParameters(proposalID);
		}
    }

    //transfers ownership of this contract to new governor
    //masterchef is the token owner, governor is the owner of masterchef
    function changeGovernor() external {
		_transferOwnership(IToken(token).governor());
    }

    function updatePools() external {
        acPool1 = IXVMCgovernor(owner()).acPool1();
        acPool2 = IXVMCgovernor(owner()).acPool2();
        acPool3 = IXVMCgovernor(owner()).acPool3();
        acPool4 = IXVMCgovernor(owner()).acPool4();
        acPool5 = IXVMCgovernor(owner()).acPool5();
        acPool6 = IXVMCgovernor(owner()).acPool6();
    }

}
