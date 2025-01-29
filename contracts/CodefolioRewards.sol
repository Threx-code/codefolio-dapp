// SPDX-License-Identifier: MIT


pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable}  from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";


contract  CodefolioRewards is ERC20, ERC20Burnable, Ownable, AccessControl
{
    using SafeERC20 for ERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    constructor() ERC20("Codefolio Rewards", "CFR") Ownable(_msgSender())
    {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(MANAGER_ROLE, _msgSender());
        
    }

    function mint(address _to, uint256 _amount) external
    {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Caller does not have right");
    
        _mint(_to, _amount);
    }

    function safeCdrTransfer(address _to, uint256 _amount) external
    {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Caller does not have right");
        uint256 cdrBal = balanceOf(address(this));
        if(_amount > cdrBal){
            transfer(_to, cdrBal);
        }else{
            transfer(_to, _amount);
        }
    }

}
