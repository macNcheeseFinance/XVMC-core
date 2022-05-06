// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.0;

interface IToken {
    function governor() external view returns (address);
}
interface IAllocation {
    function nftAllocation(address _tokenAddress, uint256 _tokenID) external view returns (uint256);
}
interface IXVMCgovernor {
    function consensusContract() external view returns (address);
}
interface IConsensus {
	function totalXVMCStaked() external view returns(uint256);
	function tokensCastedPerVote(uint256 _forID) external view returns(uint256);
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
contract xvmcNFTallocationProxy {
    struct PendingContract {
        bool isValid;
        uint256 timestamp;
        uint256 votesCommitted;
    }
    address public immutable XVMC;

    uint256 public approveThreshold = 100; // percentage required to approve (100=10%)
    uint256 public rejectThreshold = 500; // percentage required to reject (of maximum vote allocated)
    uint256 public rejectionPeriod = 7 days; // period during which the allocation contract can be rejected(after approval)

    constructor(address _xvmc) {
        XVMC = _xvmc;
    }

    mapping(address => bool) public allocationContract; 
    mapping(address => PendingContract) public pendingContract; 
    

    event SetAllocationContract(address contractAddress, bool setting);
    event SetPendingContract(address contractAddress, bool setting);
    event UpdateVotes(address contractAddress, uint256 weightedVote);
    event NotifyVote(address _contract, uint256 uintValue);

    function getAllocation(address _tokenAddress, uint256 _tokenID, address _allocationContract) external view returns (uint256) {
        if(allocationContract[_allocationContract]) {
            return IAllocation(_allocationContract).nftAllocation(_tokenAddress, _tokenID);
        } else {
            return 0;
        }
    }

    // notify "start of voting" on the frontend
    function notifyVote(address _contract) external {
        emit NotifyVote(_contract, addressToUint256(_contract));
    }

    function proposeAllocationContract(address _contract) external {
        require(!pendingContract[_contract].isValid, "already proposing");
        uint256 _contractUint = addressToUint256(_contract);
        require(!pendingContract[address(uint160(_contractUint-1))].isValid, "trying to submit veto as a proposal");
        address _consensusContract = IXVMCgovernor(IToken(XVMC).governor()).consensusContract();

        uint256 _threshold = IConsensus(_consensusContract).totalXVMCStaked() * approveThreshold / 1000;
        uint256 _weightedVote = IConsensus(_consensusContract).tokensCastedPerVote(_contractUint);

        require(_weightedVote > _threshold, "insufficient votes committed");

        pendingContract[_contract].isValid = true;
        pendingContract[_contract].timestamp = block.timestamp;
        pendingContract[_contract].votesCommitted = _weightedVote;

        emit SetPendingContract(_contract, true);
    }
    //votes commited parameter is the highest achieved
    function updateVotes(address _contract) external {
        require(pendingContract[_contract].isValid, "proposal not valid");
  
        uint256 _contractUint = addressToUint256(_contract);
        address _consensusContract = IXVMCgovernor(IToken(XVMC).governor()).consensusContract();
        uint256 _weightedVote = IConsensus(_consensusContract).tokensCastedPerVote(_contractUint);

        require(_weightedVote > pendingContract[_contract].votesCommitted, "can only update to higher vote count");

        pendingContract[_contract].votesCommitted = _weightedVote;
        
        emit UpdateVotes(_contract, _weightedVote);
    }

    function rejectAllocationContract(address _contract) external {
        require(pendingContract[_contract].isValid, "proposal not valid");
        uint256 _contractUint = addressToUint256(_contract) + 1; //+1 to vote against
        address _consensusContract = IXVMCgovernor(IToken(XVMC).governor()).consensusContract();

        uint256 _threshold = pendingContract[_contract].votesCommitted * rejectThreshold / 1000;
        uint256 _weightedVote = IConsensus(_consensusContract).tokensCastedPerVote(_contractUint);

        require(_weightedVote > _threshold, "insufficient votes committed");

        pendingContract[_contract].isValid = false;

        emit SetPendingContract(_contract, false);
    }

    function approveAllocationContract(address _contract) external {
        require(pendingContract[_contract].isValid && !allocationContract[_contract], "contract not approved or already approved");
        require(block.timestamp > (pendingContract[_contract].timestamp + rejectionPeriod), "must wait rejection period before approval");
        uint256 _contractUint = addressToUint256(_contract) + 1; //+1 to vote against
        address _consensusContract = IXVMCgovernor(IToken(XVMC).governor()).consensusContract();

        uint256 _threshold = pendingContract[_contract].votesCommitted * rejectThreshold / 1000;
        uint256 _weightedVote = IConsensus(_consensusContract).tokensCastedPerVote(_contractUint);
        if(_weightedVote > _threshold) { //reject
            pendingContract[_contract].isValid = false;
            emit SetPendingContract(_contract, false);
        } else { //enforce
            allocationContract[_contract] = true;
            emit SetAllocationContract(_contract, true);
        }
    }

    //allocation contract can also be set through the governing address
    function setAllocationContract(address _contract, bool _setting) external {
        require(msg.sender == IToken(XVMC).governor(), "only governor");
        allocationContract[_contract] = _setting;

        emit SetAllocationContract(_contract, _setting);
    }

    function setApproveThreshold(uint256 _threshold) external {
        require(msg.sender == IToken(XVMC).governor(), "only governor");
        approveThreshold = _threshold;
    }
    function setRejectThreshold(uint256 _threshold) external {
        require(msg.sender == IToken(XVMC).governor(), "only governor");
        rejectThreshold = _threshold;
    }
    function setRejectionPeriod(uint256 _period) external {
        require(msg.sender == IToken(XVMC).governor(), "only governor");
        rejectionPeriod = _period;
    }

    function addressToUint256(address _address) public pure returns (uint256) {
        return(uint256(uint160(_address)));
    }

}
