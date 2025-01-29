// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;


abstract contract ReentrancyGuard {
    uint256 private _status;
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    constructor() {
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != ENTERED, "ReentrancyGuard: reentrant call");
        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }
}