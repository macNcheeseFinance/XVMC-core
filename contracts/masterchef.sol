// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import './libs/masterchefLibs.sol';

contract XVMChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of EGGs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accXvmcPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accXvmcPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. EGGs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that EGGs distribution occurs.
        uint256 accXvmcPerShare;   // Accumulated EGGs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // The XVMC TOKEN!
    IERC20 public xvmc;
	// Old XVMC token
	IERC20 public oldToken = IERC20(0x6d0c966c8A09e354Df9C48b446A474CE3343D912);
    // Dev address.
    address public devaddr;
	//portion of inflation goes to the decentralized governance contract
	uint256 public governorFee = 618; //6.18%
    // XVMC tokens created per block.
    uint256 public XVMCPerBlock;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
	mapping(IERC20 => bool) public poolExistence;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when EGG mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
	event UpdateEmissions(address indexed user, uint256 newEmissions);

    constructor(
        IERC20 _XVMC,
        address _devaddr,
        address _feeAddress,
        uint256 _XVMCPerBlock,
        uint256 _startBlock
    ) public {
        xvmc = _XVMC;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        XVMCPerBlock = _XVMCPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
		//prevents adding a contract that is not a token/LPtoken(incompatitible)
		require(_lpToken.balanceOf(address(this)) >= 0, "incompatitible token contract");
		//prevents same LP token from being added twice
		require(!poolExistence[_lpToken], "LP pool already exists");
		
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
		poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accXvmcPerShare: 0,
            depositFeeBP: _depositFeeBP
        }));
    }

    // Update the given pool's EGG allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }


    // View function to see pending EGGs on frontend.
    function pendingEgg(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accXvmcPerShare = pool.accXvmcPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = (block.number).sub(pool.lastRewardBlock);
            uint256 xvmcReward = multiplier.mul(XVMCPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accXvmcPerShare = accXvmcPerShare.add(xvmcReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accXvmcPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = (block.number).sub(pool.lastRewardBlock);
        uint256 xvmcReward = multiplier.mul(XVMCPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        xvmc.mint(devaddr, xvmcReward.mul(governorFee).div(10000));
        xvmc.mint(address(this), xvmcReward);
        pool.accXvmcPerShare = pool.accXvmcPerShare.add(xvmcReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for EGG allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accXvmcPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeEggTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if(pool.depositFeeBP > 0){
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            }else{
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accXvmcPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accXvmcPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeEggTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accXvmcPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe xvmc transfer function, just in case if rounding error causes pool to not have enough EGGs.
    function safeEggTransfer(address _to, uint256 _amount) internal {
        uint256 xvmcBal = xvmc.balanceOf(address(this));
        if (_amount > xvmcBal) {
            xvmc.transfer(_to, xvmcBal);
        } else {
            xvmc.transfer(_to, _amount);
        }
    }
	
	function setGovernorFee(uint256 _amount) public onlyOwner {
		require(_amount <= 1000 && _amount > 0);
		governorFee = _amount;
	}

    // Update dev address by the previous dev.
    function dev(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
    }

    function setFeeAddress(address _feeAddress) public onlyOwner {
        feeAddress = _feeAddress;
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _xvmcPerBlock) public onlyOwner {
        massUpdatePools();
        XVMCPerBlock = _xvmcPerBlock;
		
		emit UpdateEmissions(tx.origin, _xvmcPerBlock);
    }

    //Only update before start of farm
    function updateStartBlock(uint256 _startBlock) public onlyOwner {
        require(block.number < startBlock, "already started");
		startBlock = _startBlock;
    }
	
	//For flexibility(can transfer to new masterchef if need be!)
	function transferTokenOwner(address _newOwner) external onlyOwner {
		xvmc.transferOwnership(_newOwner);
	}
}
