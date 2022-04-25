
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.0;

import "../libs/standard/IERC20.sol";

interface IXVMCgovernor {
    function acPool1() external returns (address);
    function acPool2() external returns (address);
    function acPool3() external returns (address);
    function acPool4() external returns (address);
    function acPool5() external returns (address);
    function acPool6() external returns (address);
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
}

interface IChange {
    function changeGovernor() external;
    function updatePools() external;
    function setAdmin() external;
}

interface IDummy {
    function updateOwnerToGovernor() external;
    function updateOwner() external;
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
        updateWalletsOwner();
        updatePoolsInSideContracts();
        updateDummysOwner(false);
        updateOldChef(true);
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

    function updateWalletsOwner() public {
        address governor = IToken(tokenXVMC).governor();

        IChange(IGovernor(governor).treasuryWallet()).changeGovernor();
        IChange(IGovernor(governor).nftWallet()).changeGovernor();
    }

    function updatePoolsInSideContracts() public {
        address governor = IToken(tokenXVMC).governor();

        IChange(IGovernor(governor).consensusContract()).updatePools();
        IChange(IGovernor(governor).basicContract()).updatePools();
    }

    function updateDummysOwner(bool _updatePools) public {
        if(_updatePools) { updatePools(); }

        IDummy(address(IacPool(acPool1).dummyToken())).updateOwnerToGovernor();
        IDummy(address(IacPool(acPool2).dummyToken())).updateOwnerToGovernor();
        IDummy(address(IacPool(acPool3).dummyToken())).updateOwnerToGovernor();
        IDummy(address(IacPool(acPool4).dummyToken())).updateOwnerToGovernor();
        IDummy(address(IacPool(acPool5).dummyToken())).updateOwnerToGovernor();
        IDummy(address(IacPool(acPool6).dummyToken())).updateOwnerToGovernor();
    }
    
    function updateOldChef(bool _dummyToken) public {
        address governor = IToken(tokenXVMC).governor();
        address _oldChefOwner = IGovernor(governor).oldChefOwner();
        
        if(_dummyToken) { 
            address _oldChefDummy = address(IacPool(_oldChefOwner).dummyToken());
            IDummy(_oldChefDummy).updateOwner();
        }
        
        IChange(_oldChefOwner).setAdmin();
    }
}
