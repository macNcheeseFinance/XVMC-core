// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libs/custom/IERC20.sol";
import "./libs/standard/Address.sol";
import "./libs/custom/SafeERC20.sol";


interface IToken {
    function governor() external view returns (address);
	function trustedContract(address _contract) external view returns (bool);
}
interface IAllocation {
    function nftAllocation(address _tokenAddress, uint256 _tokenID) external view returns (uint256);
}
interface IXVMCgovernor {
    function consensusContract() external view returns (address);
	function nftStakingPoolID() external view returns (uint256);
	function masterchef() external view returns (address);
	function delayBeforeEnforce() external view returns (uint256);
	function costToVote() external view returns (uint256);
	function nftStakingContract() external view returns (address);
}
interface IConsensus {
	function totalXVMCStaked() external view returns(uint256);
	function tokensCastedPerVote(uint256 _forID) external view returns(uint256);
}
interface INFTstaking {
	function setPoolPayout(address _poolAddress, uint256 _amount, uint256 _minServe) external;
}
interface IMasterChef {
    function poolInfo(uint256) external returns (address, uint256, uint256, uint256, uint16);
	function massUpdatePools() external;
}
interface IDummy {
	function owner() external view returns (address);
}

/*
 * TLDR of how it works;
 * If threshold of vote is met(through stake voting), the proposal can be pushed
 * Proposal can be rejected if reject threshold is met
 * If not rejected during rejection period, the proposed contract goes into effect
 * The proposed contract should contain the logic and details for actual allocations per each NFT
 * This contract acts as a proxy for the staking contract(staking contract looks up allocation through this contract)
 * And this contract looks up the actual allocation number through the valid allocation contract
 * Can contain a batch/list of NFTs, process for changing allocations, etc...
*/
contract xvmcNFTallocationProxy is Ownable {
	using SafeERC20 for IERC20;

    struct PendingContract {
        bool isValid;
        uint256 timestamp;
        uint256 votesCommitted;
    }

    struct ProposalStructure {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
        address poolAddress;
        uint256 payoutAmount;
		uint256 minServe; //minimum time required to serve before withdrawal
    }

	ProposalStructure[] public payoutProposal;

    address public immutable token;

    uint256 public approveThreshold = 100; // percentage required to approve (100=10%)
    uint256 public rejectThreshold = 500; // percentage required to reject (of maximum vote allocated)
    uint256 public rejectionPeriod = 7 days; // period during which the allocation contract can be rejected(after approval)

    mapping(address => bool) public allocationContract; 
    mapping(address => PendingContract) public pendingContract; 
    
    constructor(address _xvmc) {
        token = _xvmc;
    }

    event SetAllocationContract(address contractAddress, bool setting);
    event SetPendingContract(address contractAddress, uint256 uintValue, bool setting);
    event UpdateVotes(address contractAddress, uint256 uintValue, uint256 weightedVote);
    event NotifyVote(address _contract, uint256 uintValue, address enforcer);

	event SetPoolPayout(uint256 proposalID, uint256 depositingTokens, address forPool, uint256 payoutAmount, uint256 minServe, address enforcer, uint256 delay);
	event AddVotes(uint256 proposalID, address enforcer, uint256 tokensSacrificed, bool _for);
	event EnforceProposal(uint256 proposalID, address enforcer, bool _isSuccess);

    function getAllocation(address _tokenAddress, uint256 _tokenID, address _allocationContract) external view returns (uint256) {
        if(allocationContract[_allocationContract]) {
            return IAllocation(_allocationContract).nftAllocation(_tokenAddress, _tokenID);
        } else {
            return 0;
        }
    }

    // notify "start of voting" on the frontend
    function notifyVote(address _contract) external {
        emit NotifyVote(_contract, addressToUint256(_contract), msg.sender);
    }

    function proposeAllocationContract(address _contract) external {
        require(!pendingContract[_contract].isValid, "already proposing");
		require(block.timestamp > pendingContract[_contract].timestamp, "cool-off period required"); //in case contract is rejected
        uint256 _contractUint = addressToUint256(_contract);
        require(!pendingContract[address(uint160(_contractUint-1))].isValid, "trying to submit veto as a proposal");
        address _consensusContract = IXVMCgovernor(IToken(token).governor()).consensusContract();

        uint256 _threshold = IConsensus(_consensusContract).totalXVMCStaked() * approveThreshold / 1000;
        uint256 _weightedVote = IConsensus(_consensusContract).tokensCastedPerVote(_contractUint);

        require(_weightedVote > _threshold, "insufficient votes committed");

        pendingContract[_contract].isValid = true;
        pendingContract[_contract].timestamp = block.timestamp;
        pendingContract[_contract].votesCommitted = _weightedVote;

        emit SetPendingContract(_contract, _contractUint, true);
    }
    //votes commited parameter is the highest achieved
    function updateVotes(address _contract) external {
        require(pendingContract[_contract].isValid, "proposal not valid");
  
        uint256 _contractUint = addressToUint256(_contract);
        address _consensusContract = IXVMCgovernor(IToken(token).governor()).consensusContract();
        uint256 _weightedVote = IConsensus(_consensusContract).tokensCastedPerVote(_contractUint);

        require(_weightedVote > pendingContract[_contract].votesCommitted, "can only update to higher vote count");

        pendingContract[_contract].votesCommitted = _weightedVote;
        
        emit UpdateVotes(_contract, _contractUint, _weightedVote);
    }

    function rejectAllocationContract(address _contract) external {
        require(pendingContract[_contract].isValid, "proposal not valid");
        uint256 _contractUint = addressToUint256(_contract) + 1; //+1 to vote against
        address _consensusContract = IXVMCgovernor(IToken(token).governor()).consensusContract();

        uint256 _threshold = pendingContract[_contract].votesCommitted * rejectThreshold / 1000;
        uint256 _weightedVote = IConsensus(_consensusContract).tokensCastedPerVote(_contractUint);

        require(_weightedVote > _threshold, "insufficient votes committed");

        pendingContract[_contract].isValid = false;
		pendingContract[_contract].votesCommitted = 0;
		pendingContract[_contract].timestamp = block.timestamp + 259200; //3-day cool-off period

        emit SetPendingContract(_contract, _contractUint-1, false);
    }

    function approveAllocationContract(address _contract) external {
        require(pendingContract[_contract].isValid && !allocationContract[_contract], "contract not approved or already approved");
        require(block.timestamp > (pendingContract[_contract].timestamp + rejectionPeriod), "must wait rejection period before approval");
        uint256 _contractUint = addressToUint256(_contract) + 1; //+1 to vote against
        address _consensusContract = IXVMCgovernor(IToken(token).governor()).consensusContract();

        uint256 _threshold = pendingContract[_contract].votesCommitted * rejectThreshold / 1000;
        uint256 _weightedVote = IConsensus(_consensusContract).tokensCastedPerVote(_contractUint);
        if(_weightedVote > _threshold) { //reject
            pendingContract[_contract].isValid = false;
            emit SetPendingContract(_contract, _contractUint-1, false);
        } else { //enforce
            allocationContract[_contract] = true;
            emit SetAllocationContract(_contract, true);
        }
    }

  /**
     * Regulatory process for setting pool payout and min serve(basically to determine penalty 
	 * depending on which pool the user is harvesting their earned interest into
	 * address(0)-address(2) are used to set default harvest threshold, fee to pay, direct withdraw fee
    */
    function initiatePoolPayout(uint256 depositingTokens, address _forPoolAddress, uint256 _payout, uint256 _minServe, uint256 delay) external { 
		require(delay <= IXVMCgovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
    	require(depositingTokens >= IXVMCgovernor(owner()).costToVote(), "minimum cost to vote");
		require(
			IToken(token).trustedContract(_forPoolAddress) || _forPoolAddress == address(0) ||
					_forPoolAddress == address(1) || _forPoolAddress == address(2),
			"pools/trusted contracts only");
    
    	IERC20(token).safeTransferFrom(msg.sender, owner(), depositingTokens);
    	payoutProposal.push(
    	    ProposalStructure(true, block.timestamp, depositingTokens, 0, delay, _forPoolAddress, _payout, _minServe)
    	    );  
    	    
        emit SetPoolPayout(payoutProposal.length - 1, depositingTokens, _forPoolAddress, _payout, _minServe, msg.sender, delay);
    }
	function votePoolPayoutY(uint256 proposalID, uint256 withTokens) external {
		require(payoutProposal[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		payoutProposal[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(proposalID, msg.sender, withTokens, true);
	}
	function votePoolPayoutN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(payoutProposal[proposalID].valid, "invalid");
		
		IERC20(token).safeTransferFrom(msg.sender, owner(), withTokens);

		payoutProposal[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoPoolPayout(proposalID); }

		emit AddVotes(proposalID, msg.sender, withTokens, false);
	}
    function vetoPoolPayout(uint256 proposalID) public {
    	require(payoutProposal[proposalID].valid, "already invalid"); 
		require(payoutProposal[proposalID].firstCallTimestamp + payoutProposal[proposalID].delay < block.timestamp, "pending delay");
		require(payoutProposal[proposalID].valueSacrificedForVote < payoutProposal[proposalID].valueSacrificedAgainst, "needs more votes");
 
    	payoutProposal[proposalID].valid = false;  
    	
    	emit EnforceProposal(proposalID, msg.sender, false);
    }

    function executePoolPayout(uint256 proposalID) public {
    	require(
    	    payoutProposal[proposalID].valid &&
    	    payoutProposal[proposalID].firstCallTimestamp + IXVMCgovernor(owner()).delayBeforeEnforce() + payoutProposal[proposalID].delay < block.timestamp,
    	    "conditions not met"
    	);

		if(payoutProposal[proposalID].valueSacrificedForVote >= payoutProposal[proposalID].valueSacrificedAgainst) {
			address _stakingContract = IXVMCgovernor(owner()).nftStakingContract();

			INFTstaking(_stakingContract).setPoolPayout(payoutProposal[proposalID].poolAddress, payoutProposal[proposalID].payoutAmount, payoutProposal[proposalID].minServe);

			payoutProposal[proposalID].valid = false; 
			
			emit EnforceProposal(proposalID, msg.sender, true);
		} else {
			vetoPoolPayout(proposalID);
		}
    }

    //allocation contract can also be set through the governing address
    function setAllocationContract(address _contract, bool _setting) external {
        require(msg.sender == IToken(token).governor(), "only governor");
        allocationContract[_contract] = _setting;

        emit SetAllocationContract(_contract, _setting);
    }

    function setApproveThreshold(uint256 _threshold) external {
        require(msg.sender == IToken(token).governor(), "only governor");
        approveThreshold = _threshold;
    }
    function setRejectThreshold(uint256 _threshold) external {
        require(msg.sender == IToken(token).governor(), "only governor");
        rejectThreshold = _threshold;
    }
    function setRejectionPeriod(uint256 _period) external {
        require(msg.sender == IToken(token).governor(), "only governor");
        rejectionPeriod = _period;
    }

    function addressToUint256(address _address) public pure returns (uint256) {
        return(uint256(uint160(_address)));
    }

	function changeGovernor() external {
		_transferOwnership(IToken(token).governor());
	}

}
