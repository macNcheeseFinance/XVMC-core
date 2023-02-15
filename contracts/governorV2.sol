// SPDX-License-Identifier: NONE

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

    function harvest() external;

	function calculateHarvestXVMCRewards() external view returns (uint256);

}



interface IMasterChef {

    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) external;

    function updateEmissionRate(uint256 _xvmcPerBlock) external;

    function setFeeAddress(address _feeAddress) external;

    function dev(address _devaddr) external;

    function transferOwnership(address newOwner) external;

    function XVMCPerBlock() external returns (uint256);

    function totalAllocPoint() external returns (uint256);

    function updatePool(uint256 _pid) external;

    function owner() external returns (address);

	function setGovernorFee(uint256 _amount) external;

    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) external;

    function poolInfo(uint256) external returns (address, uint256, uint256, uint256, uint16);
	function massUpdatePools() external;
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



interface InftStaking {

    function stopEarning(uint256 _withdrawAmount) external;

    function setAdmin() external;

    function withdrawDummy(uint256 _amount) external;

    function startEarning() external;

}



interface InftAllocation {

    function setAllocationContract(address _contract, bool _setting) external;

}

interface IToken {
    function setTrustedContract(address _contractAddress, bool _setting) external;
}

interface IDummy {
    function mint(address to, uint256 amount) external;
}

interface IMaticVault {
    function setDepositFee(uint256 _depositFee) external;
    function setFundingRate(uint256 _fundingRate) external;
    function setRefShare1(uint256 _refShare1) external;
    function setRefShare2(uint256 _refShare2) external;
    function updateSettings(uint256 _defaultDirectHarvest) external;
}

interface IFarm {
    function farmMultiplierDuringBoost() external view returns (uint256);
    function memeMultiplierDuringBoost() external view returns (uint256);
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

    address public immutable token = 0x970ccEe657Dd831e9C37511Aa3eb5302C1Eb5EEe; //XVMC token

    

    //masterchef address

    address public immutable masterchef = 0x6ff40a8a1fe16075bD6008A48befB768BE08b4b0;

    address public immutable oldChefOwner = 0x27771BB243c37B35091b0A1e8b69C816249c2E71;

	

	//https://docs.polygon.technology/docs/faq/commit-chain-multisigs/

	address public immutable polygonMultisig = 0x355b8E02e7F5301E6fac9b7cAc1D6D9c86C0343f; 

	

    address public immutable consensusContract = 0xDDd4982e3E9e5C5C489321D2143b8a027f535112;

    address public immutable farmContract = 0xc2Bc56b55601E1E909Ea08ba3006d69A68d791D8; // farmsV2 contract

    address public immutable fibonacceningContract = 0xff5a8072565726A055690bd14924022DE020623A; //reward boost contract

    address public immutable basicContract = 0xEBD2e542F593d8E03543661BCc70ad2474e6DBad;

	

    address public immutable oldNftStakingContract = 0xD7bf9953d090D6Eb5fC8f6707e88Ea057beD08cB;

	address public immutable nftStakingContract = 0xEc94d2b09aD2b8493718D1edca6EE3c954E7F320;

	address public immutable nftAllocationContract = 0x765A3045902B164dA1a7619BEc58DE64cf7Bdfe2;

    address public immutable maticVault = 0x637e8158782D1006983d620C5eF80823410fF141;

    

    //Addresses for treasuryWallet and NFT wallet

    address public treasuryWallet = 0xC44D3FB20a7fA7eff7437c1C39d34A68A2046BA7;

    address public nftWallet = 0xcCb906C2233A39aA14f60d2F836EB24492D83713;

    

    //addresses for time-locked deposits(autocompounding pools)

    address public immutable acPool1 = 0xfFB71361dD8Fc3ef0831871Ec8dd51B413ed093C;

    address public immutable acPool2 = 0x9a9AEF66624C3fa77DaACcA9B51DE307FA09bd50;

    address public immutable acPool3 = 0x1F8a5D98f1e2F10e93331D27CF22eD7985EF6a12;

    address public immutable acPool4 = 0x30019481FC501aFa449781ac671103Feb0d6363C;

    address public immutable acPool5 = 0x8c96105ea574727e94d9C199c632128f1cA584cF;

    address public immutable acPool6 = 0x605c5AA14BdBf0d50a99836e7909C631cf3C8d46;

        

    //pool ID in the masterchef for respective Pool address and dummy token

    uint256 public immutable acPool1ID = 2;

    uint256 public immutable acPool2ID = 3;

    uint256 public immutable acPool3ID = 4;

    uint256 public immutable acPool4ID = 5;

    uint256 public immutable acPool5ID = 6;

    uint256 public immutable acPool6ID = 7;

	

	uint256 public immutable nftStakingPoolID = 10;



    uint256 public immutable innitTimestamp;

    

    mapping(address => uint256) private _rollBonus;

	

	mapping(address => address[]) public signaturesConfirmed; //for multi-sig

	mapping(address => mapping(address => bool)) public alreadySigned; //alreadySigned[owner][newGovernor]

	

	uint256 public newGovernorBlockDelay = 189000; //in blocks (roughly 5 days at beginning)

    

    uint256 public costToVote = 500000 * 1e18;  // 500K coins. All proposals are valid unless rejected. This is a minimum to prevent spam

    uint256 public delayBeforeEnforce = 3 days; //minimum number of TIME between when proposal is initiated and executed



    uint256 public maximumVoteTokens; // maximum tokens that can be voted with to prevent tyrany

    

    //fibonaccening event can be scheduled once minimum threshold of tokens have been collected

    uint256 public thresholdFibonaccening = 10000000000 * 1e18; //10B coins

    

    //delays for Fibonnaccening Events

    uint256 public immutable minDelay = 1 days; // has to be called minimum 1 day in advance

    uint256 public immutable maxDelay = 31 days; //1month.. is that good? i think yes

    

    uint256 public lastRegularReward = 33333000000000000000000; //remembers the last reward used(outside of boost)

    bool public eventFibonacceningActive; // prevent some functions if event is active ..threshold and durations for fibonaccening

    

    uint256 public blocksPerSecond = 434783; // divide by a million

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

    bool public initializedUpdates;

    bool public initializedBuyback;



    event SetInflation(uint256 rewardPerBlock);

    event TransferOwner(address newOwner, uint256 timestamp);

    event EnforceGovernor(address _newGovernor, address indexed enforcer);

    event GiveRolloverBonus(address recipient, uint256 amount, address poolInto);

	event Harvest(address indexed sender, uint256 callFee);

	event Multisig(address signer, address newGovernor, bool sign, uint256 idToVoteFor);

    

    constructor() {

			_rollBonus[0xfFB71361dD8Fc3ef0831871Ec8dd51B413ed093C] = 75;

			_rollBonus[0x9a9AEF66624C3fa77DaACcA9B51DE307FA09bd50] = 100;

			_rollBonus[0x1F8a5D98f1e2F10e93331D27CF22eD7985EF6a12] = 150;

			_rollBonus[0x30019481FC501aFa449781ac671103Feb0d6363C] = 250;

			_rollBonus[0x8c96105ea574727e94d9C199c632128f1cA584cF] = 350;

			_rollBonus[0x605c5AA14BdBf0d50a99836e7909C631cf3C8d46] = 500;

            innitTimestamp = block.timestamp;

    }    





    function innitializeUpdates() external {

        require(!initializedUpdates, "already updated");



        InftStaking(oldNftStakingContract).setAdmin(); // updates new governor in the old nft staking contr(act 

        InftStaking(oldNftStakingContract).stopEarning(0); // stops earnings in old nft staking contract(withdraws from chef)

        InftStaking(oldNftStakingContract).withdrawDummy(0); // withdraws from the contract to ourself

        uint256 _dummyBalance = IERC20(0xB18058232d1f945c19CC6988ccD19498F5d2853B).balanceOf(address(this)); // our dummy token balance

        IERC20(0xB18058232d1f945c19CC6988ccD19498F5d2853B).transfer(nftStakingContract, _dummyBalance); // transfers the dummy token to the new nft staking contract)

        InftStaking(nftStakingContract).setAdmin(); // updates admin in new staking contract
        InftStaking(nftStakingContract).startEarning(); // starts earning in the new nft staking contract (deposits to chef)



        InftAllocation(nftAllocationContract).setAllocationContract(0x717AFa6fe5A9857d0246bEa28730Ab482aE88379, true); // sets allocation contract for Land contract

        InftAllocation(nftAllocationContract).setAllocationContract(0x31806Bc381fac3E240AE49B387d5618AFBfC3D7B, true); // sets allocation contract for Trump Cards & SAND land
        InftAllocation(nftAllocationContract).setAllocationContract(0x53Cb95E510Ee65d692c58a7720E6fEc8b6DA8d52, true); // sets allocation contract for Lens protocol
        InftAllocation(nftAllocationContract).setAllocationContract(0xE1445bBdA7A8826a52820031FD9b342020d7644d, true); // sets allocation contract for Polygon Ape YC
        InftAllocation(nftAllocationContract).setAllocationContract(0xeCcB61076914d85E666eCdF0A005A54125B77e39, true); // sets allocation contract Eggcrypto Monsters



        IMasterChef(masterchef).add(1500, IERC20(0xf5aa9f6b046A61d83F808810547c7765C5Bbf7a2), 0, false); // 1500 is roughly 1% of rewards to begin with (150,000 total)
        IDummy(0xf5aa9f6b046A61d83F808810547c7765C5Bbf7a2).mint(maticVault, 1000000*1e18);
        InftStaking(maticVault).setAdmin();
        InftStaking(maticVault).startEarning();


        IToken(token).setTrustedContract(0xdf47e7a036A6a85F92898176b5A8B4B4b9fBF25A, false); //renounce previous farm contract
        IToken(token).setTrustedContract(farmContract, true); //set new farm contract as trusted contract

        initializedUpdates = true;
    }



    // withdraws MATIC from treasury into buyback contract

    function initTreasuryWithdraw() external {

        require(!initializedBuyback, "already executed");

        address buyBackAndBurn = 0xA2e4728c89D6dCFc93dF4b2b438E49da823Fe181;

        IXVMCtreasury(treasuryWallet).requestWithdraw(address(0), buyBackAndBurn, treasuryWallet.balance);



        initializedBuyback = true;

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

    	IMasterChef(masterchef).updatePool(8); //meme pool 8,9

    	IMasterChef(masterchef).updatePool(9);

		IMasterChef(masterchef).updatePool(10); // NFT staking

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

		

    	IMasterChef(masterchef).set(acPool1ID, (balancePool1 * 2 / 1e26), 0, false);

    	IMasterChef(masterchef).set(acPool2ID, (balancePool2 * 3 / 1e26), 0, false);

    	IMasterChef(masterchef).set(acPool3ID, (balancePool3 * 5 / 1e26), 0, false);

    	IMasterChef(masterchef).set(acPool4ID, (balancePool4 * 10 / 1e26), 0, false);

    	IMasterChef(masterchef).set(acPool5ID, (balancePool5 * 13 / 1e26), 0, false);

    	IMasterChef(masterchef).set(acPool6ID, (balancePool6 * 15 / 1e26), 0, false); 

    	

    	//equivalent to massUpdatePools() in masterchef, but we loop just through relevant pools

    	IMasterChef(masterchef).updatePool(acPool1ID);

    	IMasterChef(masterchef).updatePool(acPool2ID); 

    	IMasterChef(masterchef).updatePool(acPool3ID); 

    	IMasterChef(masterchef).updatePool(acPool4ID); 

    	IMasterChef(masterchef).updatePool(acPool5ID); 

    	IMasterChef(masterchef).updatePool(acPool6ID); 

    }

	

	function harvestAll() public {

		IacPool(acPool1).harvest();

		IacPool(acPool2).harvest();

		IacPool(acPool3).harvest();

		IacPool(acPool4).harvest();

		IacPool(acPool5).harvest();

		IacPool(acPool6).harvest();

	}



    /**

     * Harvests from all pools and rebalances rewards

     */

    function harvest() external {

        require(msg.sender == tx.origin, "no proxy/contracts");



        uint256 totalFee = pendingHarvestRewards();



		harvestAll();

        rebalancePools();

		

		lastHarvestedTime = block.timestamp;

	

		IERC20(token).safeTransfer(msg.sender, totalFee);



		emit Harvest(msg.sender, totalFee);

    }

	

	function pendingHarvestRewards() public view returns (uint256) {

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



        emit SetInflation(rewardPerBlock);

    }

	

	function rememberReward() external {

		require(msg.sender == fibonacceningContract);

		lastRegularReward = IMasterChef(masterchef).XVMCPerBlock();

	}

    

    

    function enforceGovernor() external {

        require(msg.sender == consensusContract);

		require(newGovernorRequestBlock + newGovernorBlockDelay < block.number, "time delay not yet passed");



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

        if(_arg) {
            enforceRewardReduction(true);
        } else {
            removeRewardReduction(true);
        }
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

    function updateMaticVault(uint256 _type, uint256 _amount) external {

        require(msg.sender == farmContract);

        if(_type == 0) {
            IMaticVault(maticVault).setDepositFee(_amount);
        } else if(_type == 2) {
            IMaticVault(maticVault).setFundingRate(_amount);
        } else if(_type == 3) {
            IMaticVault(maticVault).setRefShare1(_amount);
        } else if(_type == 4) {
            IMaticVault(maticVault).setRefShare2(_amount);
        } else if(_type == 5) {
            IMaticVault(maticVault).updateSettings(_amount);
        }
    }
 
	function enforceRewardReduction(bool withUpdate) private {
        uint256 allocPoint; uint16 depositFeeBP;
        uint256 farmMultiplierDuringBoost = IFarm(farmContract).farmMultiplierDuringBoost();
        uint256 memeMultiplierDuringBoost = IFarm(farmContract).memeMultiplierDuringBoost();
            
        (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(0);
        IMasterChef(masterchef).set(
            0, allocPoint * farmMultiplierDuringBoost / 10000, depositFeeBP, false
        );
        
        (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(1);
        IMasterChef(masterchef).set(
            1, allocPoint * farmMultiplierDuringBoost / 10000, depositFeeBP, false
        );

        (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(8);
        IMasterChef(masterchef).set(
            8, allocPoint * memeMultiplierDuringBoost / 10000, depositFeeBP, false
        );

        (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(9);
        IMasterChef(masterchef).set(
            9, allocPoint * memeMultiplierDuringBoost / 10000, depositFeeBP, false
        );
        
        if(withUpdate) { 
            IMasterChef(masterchef).massUpdatePools();
        }
    }

    function removeRewardReduction(bool withUpdate) private {
        uint256 allocPoint; uint16 depositFeeBP;
        uint256 farmMultiplierDuringBoost = IFarm(farmContract).farmMultiplierDuringBoost();
        uint256 memeMultiplierDuringBoost = IFarm(farmContract).memeMultiplierDuringBoost();

         (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(0);

        IMasterChef(masterchef).set(
            0, allocPoint * 10000 / farmMultiplierDuringBoost, depositFeeBP, false
        );
        
        (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(1);
        IMasterChef(masterchef).set(
            1, allocPoint * 10000 / farmMultiplierDuringBoost, depositFeeBP, false
        );

        (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(8);
        IMasterChef(masterchef).set(
            8, allocPoint * 10000 / memeMultiplierDuringBoost, depositFeeBP, false
        );

        (, allocPoint, , , depositFeeBP) = IMasterChef(masterchef).poolInfo(9);
        IMasterChef(masterchef).set(
            9, allocPoint * 10000 / memeMultiplierDuringBoost, depositFeeBP, false
        );
        
        if(withUpdate) { 
            IMasterChef(masterchef).massUpdatePools();
        }
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

	

	

	/*

	 * newGovernorBlockDelay is the delay during which the governor proposal can be voted against

	 * As the time passes, changes should take longer to enforce(greater security)

	 * Prioritize speed and efficiency at launch. Prioritize security once established

	 * Delay increases by 2500 blocks(roughly 1.6hours) per each day after launch

	 * Delay starts at 189000 blocks(roughly 5 days)

	 * After a month, delay will be roughly 7 days (increases 2days/month)

	 * After a year, 29 days. After 2 years, 53 days,...

	 * Can be ofcourse changed by replacing governor contract

	 */

	function updateGovernorChangeDelay() external {

		newGovernorBlockDelay = 189000 + (((block.timestamp - innitTimestamp) / 86400) * 2500);

	}
}
