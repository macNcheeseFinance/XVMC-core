
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.0;

import "./libs/standard/IERC20.sol";

interface IXVMCgovernor {
    function acPool1() external view returns (address);
    function acPool2() external view returns (address);
    function acPool3() external view returns (address);
    function acPool4() external view returns (address);
    function acPool5() external view returns (address);
    function acPool6() external view returns (address);
    function nftAllocationContract () external view returns (address);
	function nftStakingContract() external view returns (address);
}

interface IToken {
    function governor() external view returns (address);
}

interface IacPool {
    function setAdmin() external;
    function dummyToken() external view returns (IERC20);
}

interface IGovernor {
    function consensusContract() external view returns (address);
    function farmContract() external view returns (address);
    function fibonacceningContract() external view returns (address);
    function basicContract() external view returns (address);
    function treasuryWallet() external view returns (address);
    function nftWallet() external view returns (address);
    function oldChefOwner() external returns (address);
	function nftAllocationContract() external view returns (address);
}

interface IChange {
    function changeGovernor() external;
    function updatePools() external;
    function setAdmin() external;
    function setMasterchef() external;
}

interface INFTstaking {
	function setAdmin() external;
}

interface IMasterChef {
    function poolInfo(uint256) external returns (address, uint256, uint256, uint256, uint16);
}
contract XVMCsyncContracts {
    address public immutable tokenXVMC;
    
    address public acPool1;
    address public acPool2;
    address public acPool3;
    address public acPool4;
    address public acPool5;
    address public acPool6;


    constructor(address _xvmc) {
        tokenXVMC = _xvmc;
    }

    function updateAll() external {
        updatePoolsOwner();
        updateSideContractsOwner();
        updatePoolsInSideContracts();
        updateOldChef(true);
        updateMasterchef();
		nftStaking();
    }

    function updatePools() public {
        address governor = IToken(tokenXVMC).governor();

        acPool1 = IXVMCgovernor(governor).acPool1();
        acPool2 = IXVMCgovernor(governor).acPool2();
        acPool3 = IXVMCgovernor(governor).acPool3();
        acPool4 = IXVMCgovernor(governor).acPool4();
        acPool5 = IXVMCgovernor(governor).acPool5();
        acPool6 = IXVMCgovernor(governor).acPool6();
    }

    function updatePoolsOwner() public {
        updatePools();

        IacPool(acPool1).setAdmin();
        IacPool(acPool2).setAdmin();
        IacPool(acPool3).setAdmin();
        IacPool(acPool4).setAdmin();
        IacPool(acPool5).setAdmin();
        IacPool(acPool6).setAdmin();
    }

    function updateSideContractsOwner() public {
        address governor = IToken(tokenXVMC).governor();

        IChange(IGovernor(governor).consensusContract()).changeGovernor();
        IChange(IGovernor(governor).farmContract()).changeGovernor();
        IChange(IGovernor(governor).fibonacceningContract()).changeGovernor();
        IChange(IGovernor(governor).basicContract()).changeGovernor();
    }

    function updatePoolsInSideContracts() public {
        address governor = IToken(tokenXVMC).governor();

        IChange(IGovernor(governor).consensusContract()).updatePools();
        IChange(IGovernor(governor).basicContract()).updatePools();
    }

    //updates allocation contract owner, nft staking(admin)
    function nftStaking() public {
        address governor = IToken(tokenXVMC).governor();
		address _stakingContract = IXVMCgovernor(governor).nftStakingContract();

        IChange(IGovernor(governor).nftAllocationContract()).changeGovernor();
        INFTstaking(_stakingContract).setAdmin();
    }
    
    
    function updateMasterchef() public {
		address governor = IToken(tokenXVMC).governor();

        IChange(IGovernor(governor).farmContract()).setMasterchef();
        IChange(IGovernor(governor).fibonacceningContract()).setMasterchef();
    }
}
