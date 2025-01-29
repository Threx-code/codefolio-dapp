// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";
import {CodefolioRewards} from "./CodefolioRewards.sol";

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

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

     PoolInfo[] public poolInfo;
    uint256 public totalAllocation = 0;
    uint256 public startBlock;
    uint256 public BONUS_MULTIPLIER;

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


    function poolLength() external view returns (uint256){
        return poolInfo.length;
    }

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

    function getMultiplier(uint256 _from, uint256 _to) public view returns(uint256){
        return (_to - _from) * BONUS_MULTIPLIER;
    }


    function updateMultiplier(uint256 _multiplier) public onlyOwner{
        BONUS_MULTIPLIER = _multiplier;
    }

    function checkDuplicatePool(IERC20 _lpToken) public view {
        uint256 lengthOfPool = poolInfo.length;
        for(uint256 _pid = 0; _pid < lengthOfPool; _pid++){
            require(poolInfo[_pid].lpToken != _lpToken, "Pool already exist");
        }
    }


    function updateStakingPool() internal {
        uint256 lengthOfPool = poolInfo.length;
        uint256 points = 0;
        uint256 poolZero = poolInfo[0].allocPoint;

        for(uint256 _pid = 1; _pid < lengthOfPool; _pid++){
            points += poolInfo[_pid].allocPoint;
        }

        if(points != 0){
            points = (points / 3);
            totalAllocation = (totalAllocation - poolZero) + points;
            poolInfo[0].allocPoint = points;
        }
    }


    function addPool(uint256 _allocPoint, IERC20 _lpToken) public onlyOwner {
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

    }



      
}   