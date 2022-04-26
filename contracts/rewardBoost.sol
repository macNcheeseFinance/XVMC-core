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
    function thresholdFibonaccening() external returns (uint256);
    function eventFibonacceningActive() external returns (bool);
    function setThresholdFibonaccening(uint256 newThreshold) external;
    function fibonacciDelayed() external returns (bool);
    function setInflation(uint256 newInflation) external;
    function delayFibonacci(bool _arg) external;
    function totalFibonacciEventsAfterGrand() external returns (uint256);
    function rewardPerBlockPriorFibonaccening() external returns (uint256);
    function blocks100PerSecond() external returns (uint256);
    function changeGovernorEnforced() external returns (bool);
    function eligibleNewGovernor() external returns (address);
	function burnFromOldChef(uint256 _amount) external;
	function setActivateFibonaccening(bool _arg) external;
	function isInflationStatic() external returns (bool);
	function consensusContract() external view returns (address);
	function postGrandFibIncreaseCount() external;
}

interface IMasterChef {
    function XVMCPerBlock() external returns (uint256);
    function owner() external view returns (address);
}

interface IToken {
    function governor() external view returns (address);
}

interface IConsensus {
	function totalXVMCStaked() external view returns(uint256);
	function tokensCastedPerVote(uint256 _forID) external view returns(uint256);
}

// reward boost contract
// tldr; A reward boost is called 'Fibonaccening', could be compared to Bitcoin halvening
// When A threshold of tokens are collected, a reward boost event can be scheduled
// During the event there is a period of boosted rewards
// After the event ends, the tokens are burned and the global inflation is reduced
contract XVMCfibonaccening is Ownable {
    using SafeERC20 for IERC20;
    
    struct FibonacceningProposal {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
        uint256 rewardPerBlock;
        uint256 duration;
        uint256 startTime;
    }
    struct ProposeGrandFibonaccening{
        bool valid;
        uint256 eventDate; 
        uint256 firstCallTimestamp;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
        uint256 finalSupply;
    }
    
    FibonacceningProposal[] public fibonacceningProposals;
    ProposeGrandFibonaccening[] public grandFibonacceningProposals;

    //WARNING: careful where we are using 1e18 and where not
    uint256 public immutable goldenRatio = 1618; //1.618 is the golden ratio
    IERC20 public immutable token; //XVMC token
	
	address public immutable oldToken = 0x6d0c966c8A09e354Df9C48b446A474CE3343D912;
	
	address public immutable oldMasterchef = 0x9BD741F077241b594EBdD745945B577d59C8768e;
 
    
    //masterchef address
    address public masterchef;
    
    uint256 public lastCallFibonaccening; //stores timestamp of last grand fibonaccening event
    
    bool public eligibleGrandFibonaccening; // when big event is ready
    bool public grandFibonacceningActivated; // if upgrading the contract after event, watch out this must be true
    uint256 public desiredSupplyAfterGrandFibonaccening; // Desired supply to reach for Grand Fib Event
    
    uint256 public targetBlock; // used for calculating target block
    bool public isRunningGrand; //we use this during Grand Fib Event

    uint256 public fibonacceningActiveID;
    uint256 public fibonacceningActivatedBlock;
    
    bool public expiredGrandFibonaccening;
    
    uint256 public tokensForBurn; //tokens we draw from governor to burn for fib event

	uint256 public grandEventLength = 24 * 3600; // default Duration for the Grand Fibonaccening(the time in which 61.8% of the supply is printed)
	uint256 public delayBetweenEvents = 48 * 3600; // delay between when grand events can be triggered(default 48hrs)

    event ProposeFibonaccening(uint256 proposalID, uint256 valueSacrificedForVote, uint256 startTime, uint256 durationInBlocks, uint256 newRewardPerBlock , address indexed enforcer, uint256 delay);

    event EndFibonaccening(uint256 proposalID, address indexed enforcer);
    event CancleFibonaccening(uint256 proposalID, address indexed enforcer);
    
    event RebalanceInflation(uint256 newRewardPerBlock);
    
    event InitiateProposeGrandFibonaccening(uint256 proposalID, uint256 depositingTokens, uint256 eventDate, uint256 finalSupply, address indexed enforcer, uint256 delay);
	
	event AddVotes(uint256 _type, uint256 proposalID, address indexed voter, uint256 tokensSacrificed, bool _for);
	event EnforceProposal(uint256 _type, uint256 proposalID, address indexed enforcer, bool isSuccess);
    
    event ChangeGovernor(address newGovernor);
	
	constructor (IERC20 _XVMC, address _masterchef) {
		token = _XVMC;
		masterchef = _masterchef;
	}
    
    
    /**
     * Regulatory process for scheduling a "fibonaccening event"
    */    
    function proposeFibonaccening(uint256 depositingTokens, uint256 newRewardPerBlock, uint256 durationInBlocks, uint256 startTimestamp, uint256 delay) external {
        require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "costs to submit decisions");
        require(IERC20(token).balanceOf(owner()) >= IXVMCgovernor(owner()).thresholdFibonaccening(), "need to collect penalties before calling");
        require(!(IXVMCgovernor(owner()).eventFibonacceningActive()), "Event already running");
        require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
        require(
            startTimestamp > block.timestamp + delay + (24*3600) + IXVMCgovernor(owner()).delayBeforeEnforce() && 
            startTimestamp - block.timestamp <= 21 days, "max 21 days"); 
        require(
            (newRewardPerBlock * durationInBlocks) < (getTotalSupply() * 23 / 100),
            "Safeguard: Can't print more than 23% of tokens in single event"
        );
		require(newRewardPerBlock > goldenRatio, "can't go below goldenratio"); //would enable grand fibonaccening
		//duration(in blocks) must be lower than amount of blocks mined in 30days(can't last more than roughly 30days)
		//30(days)*24(hours)*3600(seconds) * 100 (to negate x100 blocks per second) = 259200000
		uint256 amountOfBlocksIn30Days = 259200000 / IXVMCgovernor(owner()).blocks100PerSecond();
		require(durationInBlocks <= amountOfBlocksIn30Days, "maximum 30days duration");
    
		IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens); 
        fibonacceningProposals.push(
            FibonacceningProposal(true, block.timestamp, depositingTokens, 0, delay, newRewardPerBlock, durationInBlocks, startTimestamp)
            );
    	
    	emit ProposeFibonaccening(fibonacceningProposals.length - 1, depositingTokens, startTimestamp, durationInBlocks, newRewardPerBlock, msg.sender, delay);
    }
	function voteFibonacceningY(uint256 proposalID, uint256 withTokens) external {
		require(fibonacceningProposals[proposalID].valid, "invalid");
		require(fibonacceningProposals[proposalID].firstCallTimestamp + fibonacceningProposals[proposalID].delay + IXVMCgovernor(owner()).delayBeforeEnforce() > block.timestamp, "past the point of no return"); 
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		fibonacceningProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(0, proposalID, msg.sender, withTokens, true);
	}
	function voteFibonacceningN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(fibonacceningProposals[proposalID].valid, "invalid");
		require(fibonacceningProposals[proposalID].firstCallTimestamp + fibonacceningProposals[proposalID].delay + IXVMCgovernor(owner()).delayBeforeEnforce() > block.timestamp, "past the point of no return"); 
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		fibonacceningProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoFibonaccening(proposalID); }
		
		emit AddVotes(0, proposalID, msg.sender, withTokens, false);
	}
    function vetoFibonaccening(uint256 proposalID) public {
    	require(fibonacceningProposals[proposalID].valid == true, "Invalid proposal"); 
		require(fibonacceningProposals[proposalID].firstCallTimestamp + fibonacceningProposals[proposalID].delay <= block.timestamp, "pending delay");
		require(fibonacceningProposals[proposalID].valueSacrificedForVote < fibonacceningProposals[proposalID].valueSacrificedAgainst, "needs more votes");
 
    	fibonacceningProposals[proposalID].valid = false; 
    	
    	emit EnforceProposal(0, proposalID, msg.sender, false);
    }

    /**
     * Activates a valid fibonaccening event
     * 
    */
    function leverPullFibonaccening(uint256 proposalID) public {
		require(!(IXVMCgovernor(owner()).fibonacciDelayed()), "event has been delayed");
        require(
            IERC20(token).balanceOf(owner()) >= IXVMCgovernor(owner()).thresholdFibonaccening(),
            "needa collect penalties");
    	require(fibonacceningProposals[proposalID].valid == true, "invalid proposal");
    	require(block.timestamp >= fibonacceningProposals[proposalID].startTime, "can only start when set");
    	require(!(IXVMCgovernor(owner()).eventFibonacceningActive()), "already active");
		require(!grandFibonacceningActivated || (expiredGrandFibonaccening && !isRunningGrand), "not available during the grand boost event");
    	
    	if(fibonacceningProposals[proposalID].valueSacrificedForVote >= fibonacceningProposals[proposalID].valueSacrificedAgainst) {
			//IERC20(token).safeTransferFrom(msg.sender, owner(), IXVMCgovernor(owner()).costToVote()); 
			tokensForBurn = IXVMCgovernor(owner()).thresholdFibonaccening();
			IERC20(token).safeTransferFrom(owner(), address(this), tokensForBurn); 
			
			IXVMCgovernor(owner()).setInflation(fibonacceningProposals[proposalID].rewardPerBlock);
			
			fibonacceningProposals[proposalID].valid = false;
			fibonacceningActiveID = proposalID;
			fibonacceningActivatedBlock = block.number;
			IXVMCgovernor(owner()).setActivateFibonaccening(true);
			
			emit EnforceProposal(0, proposalID, msg.sender, true);
		} else {
			vetoFibonaccening(proposalID);
		}
    }
    
     /**
     * Ends fibonaccening event 
     * sets new inflation  
     * burns the tokens
    */
    function endFibonaccening() external {
        require(IXVMCgovernor(owner()).eventFibonacceningActive(), "no active event");
        require(
            block.number >= fibonacceningActivatedBlock + fibonacceningProposals[fibonacceningActiveID].duration, 
            "not yet expired"
           ); 
        
        uint256 newAmount = calculateUpcomingRewardPerBlock();
        
        IXVMCgovernor(owner()).setInflation(newAmount);
        IXVMCgovernor(owner()).setActivateFibonaccening(false);
        
    	IERC20(token).burn(tokensForBurn); // burns the tokens - "fibonaccening" sacrifice
		IXVMCgovernor(owner()).burnFromOldChef(0); //burns all the tokens in old chef
		
		//if past 'grand fibonaccening' increase event count
		if(!isRunningGrand && expiredGrandFibonaccening) {
			IXVMCgovernor(owner()).postGrandFibIncreaseCount();
		}
		
    	emit EndFibonaccening(fibonacceningActiveID, msg.sender);
    }
    

    /**
     * In case we have multiple valid fibonaccening proposals
     * When the event is enforced, all other valid proposals can be invalidated
     * Just to clear up the space
    */
    function cancleFibonaccening(uint256 proposalID) external {
        require(IXVMCgovernor(owner()).eventFibonacceningActive(), "fibonaccening active required");

        require(fibonacceningProposals[proposalID].valid, "must be valid to negate ofc");
        
        fibonacceningProposals[proposalID].valid = false;
        emit CancleFibonaccening(proposalID, msg.sender);
    }
    
    /**
     * After the Grand Fibonaccening event, the inflation reduces to roughly 1.618% annually
     * On each new Fibonaccening event, it further reduces by Golden ratio(in percentile)
	 *
     * New inflation = Current inflation * ((100 - 1.618) / 100)
     */
    function rebalanceInflation() external {
        require(IXVMCgovernor(owner()).totalFibonacciEventsAfterGrand() > 0, "Only after the Grand Fibonaccening event");
        require(!(IXVMCgovernor(owner()).eventFibonacceningActive()), "Event is running");
		bool isStatic = IXVMCgovernor(owner()).isInflationStatic();
        
		uint256 initialSupply = getTotalSupply();
		uint256 _factor = goldenRatio;
		
		// if static, then inflation is 1.618% annually
		// Else the inflation reduces by 1.618%(annually) on each event
		if(!isStatic) {
			for(uint256 i = 0; i < IXVMCgovernor(owner()).totalFibonacciEventsAfterGrand(); i++) {
				_factor = _factor * 98382 / 100000; //factor is multiplied * 1000 (number is 1618, when actual factor is 1.618)
			}
		}
		
		// divide by 1000 to turn 1618 into 1.618% (and then divide farther by 100 to convert percentage)
        uint256 supplyToPrint = initialSupply * _factor / 100000; 
		
        uint256 rewardPerBlock = supplyToPrint / (365 * 24 * 360000 / IXVMCgovernor(owner()).blocks100PerSecond());
        IXVMCgovernor(owner()).setInflation(rewardPerBlock);
       
        emit RebalanceInflation(rewardPerBlock);
    }
    
       /**
     * If inflation is to drop below golden ratio, the grand fibonaccening event is ready
     */
    function isGrandFibonacceningReady() external {
		require(!eligibleGrandFibonaccening);
        if((IMasterChef(masterchef).XVMCPerBlock() - goldenRatio * 1e18) <= goldenRatio * 1e18) { //we x1000'd the supply so 1e18
            eligibleGrandFibonaccening = true;
        }
    }

    /**
     * The Grand Fibonaccening Event, only happens once
	 * A lot of Supply is printed (x1.618 - x1,000,000)
	 * People like to buy on the way down
	 * People like high APYs
	 * People like to buy cheap coins
	 * Grand Fibonaccening ain't happening for quite some time... 
	 * We could add a requirement to vote through consensus for the "Grand Fibonaccening" to be enforced
     */    
    function initiateProposeGrandFibonaccening(uint256 depositingTokens, uint256 eventDate, uint256 finalSupply, uint256 delay) external {
    	require(eligibleGrandFibonaccening && !grandFibonacceningActivated);
		require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
    	require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "there is a minimum cost to vote");
		uint256 _totalSupply = getTotalSupply();
    	require(finalSupply >= (_totalSupply * 1618 / 1000) && finalSupply <= (_totalSupply * 1000000));
    	require(eventDate > block.timestamp + delay + (7*24*3600) + IXVMCgovernor(owner()).delayBeforeEnforce());
    	
    	
    	IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens);
    	grandFibonacceningProposals.push(
    	    ProposeGrandFibonaccening(true, eventDate, block.timestamp, depositingTokens, 0, delay, finalSupply)
    	    );
    
        emit EnforceProposal(1, grandFibonacceningProposals.length - 1, msg.sender, true);
    }
	function voteGrandFibonacceningY(uint256 proposalID, uint256 withTokens) external {
		require(grandFibonacceningProposals[proposalID].valid, "invalid");
		require(grandFibonacceningProposals[proposalID].eventDate - (7*24*3600) > block.timestamp, "past the point of no return"); //can only be cancled up until 7days before event
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		grandFibonacceningProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(1, proposalID, msg.sender, withTokens, true);
	}
	function voteGrandFibonacceningN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(grandFibonacceningProposals[proposalID].valid, "invalid");
		require(grandFibonacceningProposals[proposalID].eventDate - (7*24*3600) > block.timestamp, "past the point of no return"); //can only be cancled up until 7days before event
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		grandFibonacceningProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoProposeGrandFibonaccening(proposalID); }

		emit AddVotes(1, proposalID, msg.sender, withTokens, false);
	}
	/*
	* can be vetto'd during delayBeforeEnforce period.
	* afterwards it can not be cancled anymore
	* but it can still be front-ran by earlier event
	*/
    function vetoProposeGrandFibonaccening(uint256 proposalID) public {
    	require(grandFibonacceningProposals[proposalID].valid, "already invalid");
		require(grandFibonacceningProposals[proposalID].firstCallTimestamp + grandFibonacceningProposals[proposalID].delay + IXVMCgovernor(owner()).delayBeforeEnforce() <= block.timestamp, "pending delay");
		require(grandFibonacceningProposals[proposalID].valueSacrificedForVote < grandFibonacceningProposals[proposalID].valueSacrificedAgainst, "needs more votes");

    	grandFibonacceningProposals[proposalID].valid = false;  
    	
    	emit EnforceProposal(1, proposalID, msg.sender, false);
    }
    
	
    function grandFibonacceningEnforce(uint256 proposalID) public {
        require(!grandFibonacceningActivated, "already called");
        require(grandFibonacceningProposals[proposalID].valid && grandFibonacceningProposals[proposalID].eventDate <= block.timestamp, "not yet valid");
		
		address _consensusContract = IXVMCgovernor(owner()).consensusContract();
		
		uint256 _totalStaked = IConsensus(_consensusContract).totalXVMCStaked();
		
		//to approve grand fibonaccening, more tokens have to be sacrificed for vote ++
		// more stakes(locked shares) need to vote in favor than against it
		//to vote in favor, simply vote for proposal ID of maximum uint256 number - 1
		uint256 _totalVotedInFavor = IConsensus(_consensusContract).tokensCastedPerVote(type(uint256).max - 1);
		uint256 _totalVotedAgainst= IConsensus(_consensusContract).tokensCastedPerVote(type(uint256).max);
		
        require(_totalVotedInFavor >= _totalStaked * 25 / 100
                    || _totalVotedAgainst >= _totalStaked * 25 / 100,
                             "minimum 25% weighted vote required");

		if(grandFibonacceningProposals[proposalID].valueSacrificedForVote >= grandFibonacceningProposals[proposalID].valueSacrificedAgainst
				&& _totalVotedInFavor > _totalVotedAgainst) {
			grandFibonacceningActivated = true;
			grandFibonacceningProposals[proposalID].valid = false;
			desiredSupplyAfterGrandFibonaccening = grandFibonacceningProposals[proposalID].finalSupply;
			
			emit EnforceProposal(1, proposalID, msg.sender, true);
		} else {
			grandFibonacceningProposals[proposalID].valid = false;  
    	
			emit EnforceProposal(1, proposalID, msg.sender, false);
		}
    }
    
    /**
     * Function handling The Grand Fibonaccening
	 *
     */
    function grandFibonacceningRunning() external {
        require(grandFibonacceningActivated && !expiredGrandFibonaccening);
        
        if(isRunningGrand){
            require(block.number >= targetBlock, "target block not yet reached");
            IXVMCgovernor(owner()).setInflation(0);
            isRunningGrand = false;
			
			//incentive to stop the event in time
			if(IERC20(token).balanceOf(owner()) >= IXVMCgovernor(owner()).costToVote() * 42) {
				IERC20(token).safeTransferFrom(owner(), payable(msg.sender), IXVMCgovernor(owner()).costToVote() * 42);
			}
        } else {
			require(!(IXVMCgovernor(owner()).fibonacciDelayed()), "event has been delayed");
			uint256 _totalSupply = getTotalSupply();
            require(
                ( _totalSupply * goldenRatio * goldenRatio / 1000000) < desiredSupplyAfterGrandFibonaccening, 
                "Last 2 events happen at once"
                );
			// Just a simple implementation that allows max once per day at a certain time
            require(
                (block.timestamp % 86400) / 3600 >= 16 && (block.timestamp % 86400) / 3600 <= 18,
                "can only call between 16-18 UTC"
            );
			require(block.timestamp - lastCallFibonaccening > delayBetweenEvents);
			
			lastCallFibonaccening = block.timestamp;
            uint256 targetedSupply =  _totalSupply * goldenRatio / 1000;
			uint256 amountToPrint = targetedSupply - _totalSupply; // (+61.8%)
            
			//printing the amount(61.8% of supply) in uint256(grandEventLength) seconds ( blocks in second are x100 )
            uint256 rewardPerBlock = amountToPrint / (grandEventLength * 100 / IXVMCgovernor(owner()).blocks100PerSecond()); 
			targetBlock = block.number + (amountToPrint / rewardPerBlock);
            IXVMCgovernor(owner()).setInflation(rewardPerBlock);
			
            isRunningGrand = true;
        }
    
    }
    
    /**
     * During the last print of the Grand Fibonaccening
     * It prints up to "double the dose" in order to reach the desired supply
     * Why? to create a big decrease in the price, moving away from everyone's 
     * buy point. It creates a big gap with no overhead resistance, creating the potential for
     * the price to move back up effortlessly
     */
    function startLastPrintGrandFibonaccening() external {
        require(!(IXVMCgovernor(owner()).fibonacciDelayed()), "event has been delayed");
        require(grandFibonacceningActivated && !expiredGrandFibonaccening && !isRunningGrand);
		uint256 _totalSupply = getTotalSupply();
        require(
             _totalSupply * goldenRatio * goldenRatio / 1000000 >= desiredSupplyAfterGrandFibonaccening,
            "on the last 2 we do it in one, call lastprint"
            );
        
		require(block.timestamp - lastCallFibonaccening > delayBetweenEvents, "pending delay");
        require((block.timestamp % 86400) / 3600 >= 16, "only after 16:00 UTC");
        
        uint256 rewardPerBlock = ( desiredSupplyAfterGrandFibonaccening -  _totalSupply ) / (grandEventLength * 100 / IXVMCgovernor(owner()).blocks100PerSecond()); //prints in desired time
		targetBlock = (desiredSupplyAfterGrandFibonaccening -  _totalSupply) / rewardPerBlock;
        IXVMCgovernor(owner()).setInflation(rewardPerBlock);
                
        isRunningGrand = true;
        expiredGrandFibonaccening = true;
    }
    function expireLastPrintGrandFibonaccening() external {
        require(isRunningGrand && expiredGrandFibonaccening);
        require(block.number >= (targetBlock-7));
        
		uint256 _totalSupply = getTotalSupply();
		uint256 tokensToPrint = ( _totalSupply * goldenRatio / 1000) -  _totalSupply;
		
        uint256 newEmissions =  tokensToPrint / (365 * 24 * 360000 / IXVMCgovernor(owner()).blocks100PerSecond()); 
		
        IXVMCgovernor(owner()).setInflation(newEmissions);
        isRunningGrand = false;
		
		//incentive to stop the event in time
		if(IERC20(token).balanceOf(owner()) >= IXVMCgovernor(owner()).costToVote() * 50) {
			IERC20(token).safeTransferFrom(owner(), payable(msg.sender), IXVMCgovernor(owner()).costToVote() * 50);
		}
    }
	
  function setMasterchef() external {
		masterchef = IMasterChef(address(token)).owner();
    }
    
    //transfers ownership of this contract to new governor
    //masterchef is the token owner, governor is the owner of masterchef
    function changeGovernor() external {
		_transferOwnership(IToken(address(token)).governor());
    }
    
    // this is unneccesary until the Grand Fibonaccening is actually to happen
    // Should perhaps add a proposal to regulate the length and delay
    function updateDelayBetweenEvents(uint256 _delay) external onlyOwner {
		delayBetweenEvents = _delay;
    }
    function updateGrandEventLength(uint256 _length) external onlyOwner {
    	grandEventLength = _length;
    }
    
    function getTotalSupply() private view returns (uint256) {
         return (token.totalSupply() +
					1000 * (IERC20(oldToken).totalSupply() - IERC20(oldToken).balanceOf(address(token))));
    }

    
    /**
     * After the Fibonaccening event ends, global inflation reduces
     * by -1.618 tokens/block prior to the Grand Fibonaccening and
     * by 1.618 percentile after the Grand Fibonaccening ( * ((100-1.618) / 100))
    */
    function calculateUpcomingRewardPerBlock() public returns(uint256) {
        if(!expiredGrandFibonaccening) {
            return IXVMCgovernor(owner()).rewardPerBlockPriorFibonaccening() - goldenRatio * 1e18;
        } else {
            return IXVMCgovernor(owner()).rewardPerBlockPriorFibonaccening() * 98382 / 100000; 
        }
    }
}
