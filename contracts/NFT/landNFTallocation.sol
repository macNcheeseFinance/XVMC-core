//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

contract NftAllocationSpecific {
	address public immutable landNftContract;
	address public immutable initAddress;
	
	uint256 public baseAllocation = 25 * 1e6 *1e18; //25M

    mapping(uint256 => uint256) public allocation;

    constructor(address _contract) {
        landNftContract = _contract;
	initAddress = msg.sender;
    }
	
	function nftAllocation(address _tokenAddress, uint256 _tokenID) external view returns (uint256) {
        require(_tokenAddress == landNftContract, "wrong NFT contract");
		return allocation[_tokenID];
	}

    function initialize(uint256 startId, uint256[] calldata _allocations) external {
    	require(msg.sender == initAddress, "not allowed");
        require(allocation[9999] == 0, "already initialized");
        for(uint i=0; i < _allocations.length; i++) {
            allocation[i] = _allocations[startId + i];
        }
    }

    function getAllocationManually(uint256 _tokenID) external view returns (uint256) {
			uint256 _value = baseAllocation;
            uint256 _occurence = 0;
            uint256 _moduloNum = 20;
		for(uint i=0; i< _tokenID; i++) {
            if(_occurence > 50) {
                _moduloNum = 200;
            }
            if(i % _moduloNum == 0) {
                _value = _value * (1000 - _occurence) / 1000;
                _occurence++;
            }
		}
		return _value;
	}
}
