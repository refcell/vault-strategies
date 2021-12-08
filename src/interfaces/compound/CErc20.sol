// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.10;

import "./CToken.sol";

/**
 * @title Compound's CErc20 Contract
 * @notice CTokens which wrap an EIP-20 underlying
 * @author Compound
 */
interface CErc20 is CToken {
    function balanceOf(address sender) external returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function underlying() external view returns (address);
    function liquidateBorrow(address borrower, uint256 repayAmount, CToken cTokenCollateral) external returns (uint);
}