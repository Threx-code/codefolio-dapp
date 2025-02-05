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

    modifier onlyManager() {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Caller is not a manager");
        _;
    }

    function mint(address _to, uint256 _amount) external onlyManager {
        _mint(_to, _amount);
    }

    function safeCdrTransfer(address _to, uint256 _amount) external onlyManager {
        uint256 cdrBal = balanceOf(address(this));
        _transfer(address(this), _to, _amount > cdrBal ? cdrBal : _amount);
    }

    function burn(uint256 _amount) public override onlyOwner {
        super.burn(_amount);
    }

}
