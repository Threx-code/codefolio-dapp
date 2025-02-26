// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";
import {CodefolioRewards} from "./CodefolioRewards.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MasterContract is Ownable, ReentrancyGuard
{
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 pendingReward;
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 rewardTokenPerShare;
    }

    CodefolioRewards cdr;
    address public devAddr;
    uint256 public cdrPerBlock;
    PoolInfo[] public poolInfo;
    uint256 public totalAllocation = 0;
    uint256 public startBlock;
    uint256 public BONUS_MULTIPLIER;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event PoolAdded(address indexed lpToken, uint256 allocPoint, uint256 lastRewardBlock);
    event PoolUpdated(address indexed lpToken, uint256 allocPoint, uint256 lastRewardBlock);
    
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        CodefolioRewards _cdr,
        address _devAddr,
        uint256 _cdrPerBlock,
        uint256 _startBlock,
        uint256 _multiplier
    ) Ownable(_msgSender()){
        cdr = _cdr;
        devAddr = _devAddr;
        cdrPerBlock = _cdrPerBlock;
        startBlock = _startBlock;
        BONUS_MULTIPLIER = _multiplier;

        // staking pool
        poolInfo.push(
            PoolInfo({
                lpToken: _cdr,
                allocPoint: 10000,
                lastRewardBlock: startBlock,
                rewardTokenPerShare: 0
            })
        );

        totalAllocation = 10000;
    }


     modifier validatePool(uint256 _pid){
        require(_pid < poolInfo.length, "Pool does not exist");
        _;
    }


    /**
     * @notice Retrieves the total number of pools.
     * @dev Returns the length of the `poolInfo` array, representing the total number of liquidity pools.
     * @return uint256 The total number of pools.
     */
    function poolLength() external view returns (uint256){
        return poolInfo.length;
    }

    /**
     * @notice Retrieves information about a specific pool.
     * @dev Returns key details of the specified pool, including the LP token address,
     *      allocation points, last reward distribution block, and reward per share.
     * @param _pid The ID of the pool.
     * @return lpToken The address of the LP token associated with the pool.
     * @return allocPoint The allocation points assigned to the pool.
     * @return lastRewardBlock The last block number at which rewards were distributed.
     * @return rewardTokenPerShare The accumulated reward tokens per share for the pool.
     */
    function getPoolInfo(uint256 _pid) public view returns (
        address lpToken,
        uint256 allocPoint,
        uint256 lastRewardBlock,
        uint256 rewardTokenPerShare

    ){
        PoolInfo storage pool = poolInfo[_pid];
        return (
            address(pool.lpToken),
            pool.allocPoint,
            pool.lastRewardBlock,
            pool.rewardTokenPerShare
        );
    }


    /**
     * @notice Calculates the multiplier for a given range of pools.
     * @dev The multiplier is computed by multiplying the difference between the 
     *      two pool numbers (_from and _to) by the BONUS_MULTIPLIER constant.
     *      This function helps in determining the reward multiplier for a specified pool range.
     * @param _from The starting pool number.
     * @param _to The ending pool number.
     * @return uint256 The calculated multiplier for the specified pool range.
     */
    function getMultiplier(uint256 _from, uint256 _to) public view returns(uint256){
        if(_to <= _from) return 0; // prevent negative multipliers

        return (_to - _from) * BONUS_MULTIPLIER;
    }

    function calcTokenReward(uint256 _multiplier, uint256 _poolAllocPoint) internal view returns(uint256){
        if(totalAllocation == 0) return 0; // Prevent division by zero

        return (_multiplier * cdrPerBlock * _poolAllocPoint) / totalAllocation;
    }


    /**
     * @notice Updates the reward bonus multiplier.
     * @dev This function allows the contract owner to update the bonus multiplier, 
     *      which affects the reward calculations. The function can only be called by the owner.
     * @param _multiplier The new multiplier value to be set.
     * @dev The new multiplier will be used in reward calculations across the contract.
     */
    function updateMultiplier(uint256 _multiplier) public onlyOwner{
        BONUS_MULTIPLIER = _multiplier;
    }

    /**
     * @notice Checks if a pool with the given Liquidity Pool (LP) token already exists.
     * @param _lpToken The address of the Liquidity Pool token to check for duplication.
     * @dev This function iterates through all existing pools and verifies that the provided LP token
     *      is not already associated with an existing pool. If a duplicate pool is found, an error is thrown.
     *      The function uses a `require` statement to enforce this check.
     * @custom:throw Error "Pool already exists" if a pool with the same LP token is found.
     */
    function checkDuplicatePool(IERC20 _lpToken) public view {
        uint256 lengthOfPool = poolInfo.length;
        for(uint256 _pid = 0; _pid < lengthOfPool; _pid++){
            require(poolInfo[_pid].lpToken != _lpToken, "Pool already exist");
        }
    }

    /**
     * @notice Updates the staking pool's allocation points.
     * @dev Recalculates the allocation points for the staking pool.
     * @dev The first pool (index 0) is always the staking pool.
     *      The new allocation points are set as one-third of the total allocation points of other pools.
     *      Ensures dynamic adjustment of staking rewards based on other pools' allocations.
     */
    function updateStakingPool() internal {
        uint256 lengthOfPool = poolInfo.length;
        if(lengthOfPool == 0) return; // Prevent out-of-bounds error
        uint256 points = 0;
        uint256 poolZero = poolInfo[0].allocPoint;

        for(uint256 _pid = 1; _pid < lengthOfPool; _pid++){
            points += poolInfo[_pid].allocPoint;
        }

        if(points != 0){
            points /= 3;
            totalAllocation = (totalAllocation - poolZero) + points;
            poolInfo[0].allocPoint = points;
        }
    }


    /**
     * @notice Adds a new pool to the contract
     * @param _allocPoint The allocation points for the new pool
     * @param _lpToken The address of the Liquidity Pool token associated with the new pool
     * @dev This function performs several tasks:
     *      - First, it checks if the pool already exists using the `checkDuplicatePool` function to prevent duplicates.
     *      - Then, it calculates the last reward block (either the current block or the start block, whichever is greater).
     *      - The function increases the `totalAllocation` by the provided allocation points.
     *      - A new pool is added to the `poolInfo` array, initializing the `lpToken`, `allocPoint`, `lastRewardBlock`, and `rewardTokenPerShare` values.
     *      - Finally, it calls `updateStakingPool` to update the staking pool allocation.
     * @custom:throw Error "Pool already exists" if the pool with the same LP token is found.
     * @custom:emit Emits an event to log the addition of a new pool (if events are included in the contract).
     */
    function addPool(uint256 _allocPoint, IERC20 _lpToken) public onlyOwner {
        require(address(_lpToken) != address(0), "Invalid LP token address");
        require(_allocPoint > 0, "Allocation point must be greater than 0");
        
        checkDuplicatePool(_lpToken);

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocation += _allocPoint;

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                rewardTokenPerShare: 0
            })
        );

        updateStakingPool();

        emit PoolAdded(address(_lpToken), _allocPoint, lastRewardBlock);
    }


   
    /**
     * @notice Updates the given pool's reward variables.
     * @dev This function recalculates and distributes reward tokens to the pool.
     *      - It ensures rewards are only updated when necessary.
     *      - If no LP tokens are staked, it updates the last reward block and exits.
     *      - Rewards are minted for both the developer and the staking pool.
     *      - The function also updates the `rewardTokenPerShare` for future reward calculations.
     * 
     * @param _pid The ID of the pool to update.
     */
    function updatePool(uint256 _pid) public validatePool(_pid) onlyOwner{
        PoolInfo storage pool = poolInfo[_pid];
        if(block.number < pool.lastRewardBlock){
            return; // Exit if the current block is before the last reward block
        }

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if(lpSupply == 0 || totalAllocation == 0){
            pool.lastRewardBlock = block.number;
            return; // Exit if no LP tokens are staked
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = calcTokenReward(multiplier, pool.allocPoint);

        require(address(cdr) != address(0), "Invalid CDR token address");

        cdr.mint(devAddr, tokenReward / 10); // Mint 10% of rewards to the developer
        cdr.mint(address(cdr), tokenReward); /// Mint full reward tokens to the CDR contract


         // Update the accumulated reward per LP token, using 1e12 as a precision factor
        pool.rewardTokenPerShare = pool.rewardTokenPerShare + (tokenReward * 1e12) / lpSupply;

        // Update last reward block to the current block
        pool.lastRewardBlock = block.number;

        emit PoolUpdated(address(pool.lpToken), pool.allocPoint, pool.lastRewardBlock);
    }


    function massPoolUpdate() public {
        uint256 lengthOfPool = poolInfo.length;
        for(uint256 _pid = 0; _pid < lengthOfPool; _pid++){
            updatePool(_pid);
        }
    }


    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner validatePool(_pid){
        if(_withUpdate){
            massPoolUpdate();
        }

        uint256 previousAllocPoint = poolInfo[_pid].allocPoint;
        
        if(previousAllocPoint != _allocPoint){
            poolInfo[_pid].allocPoint = _allocPoint;

            totalAllocation = totalAllocation - previousAllocPoint + _allocPoint;
            updateStakingPool();
        }
    }


    function pendingReward(uint256 _pid, address _user) public view validatePool(_pid) returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 rewardTokenPershare = pool.rewardTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        if(block.number > pool.lastRewardBlock && lpSupply > 0){
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tokenReward = calcTokenReward(multiplier, pool.allocPoint);
            
            // calculate the updated reward Token per share
            rewardTokenPershare += (tokenReward * 1e12) / lpSupply;
        }

        return (user.amount * rewardTokenPershare) / 1e12 - user.pendingReward;
    }


    function stake(uint256 _pid, uint256 _amount) public validatePool(_pid) nonReentrant{
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];

        updatePool(_pid);

        if(user.amount > 0){
            uint256 pending = (user.amount * pool.rewardTokenPerShare) / 1e12 - user.pendingReward;
            
            if(pending > 0){
                safeCdrTransfer(_msgSender(), pending);
            }
        }

        if(_amount > 0){
            pool.lpToken.transferFrom(_msgSender(), address(this), _amount);
            user.amount += _amount;
        }

        user.pendingReward = (user.amount * pool.rewardTokenPerShare) / 1e12;

        emit Deposit(_msgSender(), _pid, _amount);
    }


    function unstake(uint256 _pid, uint256 _amount) public validatePool(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];

        require(_amount > 0, "Amount must be greater than 0");
        require(user.amount >= _amount, "Insufficient balance"); // To prevent 

        updatePool(_pid);

        if(user.amount > 0){
            uint256 pending = (user.amount * pool.rewardTokenPerShare) / 1e12 - user.pendingReward;
            if(pending > 0){
                safeCdrTransfer(_msgSender(), pending);
            }
        }

        if(_amount > 0){
            user.amount = user.amount - _amount;
            pool.lpToken.transfer(address(_msgSender()), _amount);
        }

        user.pendingReward = (user.amount * pool.rewardTokenPerShare) / 1e12;
        emit Withdraw(_msgSender(), _pid, _amount);
    }


    function autoCompound() public nonReentrant{
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][_msgSender()];

        if(user.amount > 0){
            uint256 pending = (user.amount * pool.rewardTokenPerShare) / 1e12 - user.pendingReward;
            if(pending > 0){
                user.amount += pending;
            }
        }

        user.pendingReward = (user.amount * pool.rewardTokenPerShare) / 1e12;
    }


    function emergencyWidraw(uint256 _pid) public validatePool(_pid) nonReentrant{
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];

        uint256 amount = user.amount;
        require(amount > 0, "Insufficient balance"); // Ensure non zero withdrawl

        user.amount = 0;
        user.pendingReward = 0;

        pool.lpToken.transfer(address(_msgSender()), amount);

        emit EmergencyWithdraw(_msgSender(), _pid, amount);
    }


    function changeDev(address _dev) public{
        require(_dev != address(0), "Invalid address");
        require(_dev != devAddr, "Same address");
        require(_msgSender() == devAddr, "Unauthorized");
        devAddr = _dev;
    }


    function safeCdrTransfer(address _to, uint256 _amount) internal {
        cdr.safeCdrTransfer(_to, _amount);
    }



      
}   