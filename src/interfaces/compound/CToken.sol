// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.10;

/**
 * @title Compound's CToken Contract
 * @notice Abstract base for CTokens
 * @author Compound
 */
interface CToken {
    function admin() external returns (address);
    function pendingAdmin() external returns (address);
    function comptroller() external returns (address);
    function interestRateModel() external returns (address);
    function initialExchangeRateMantissa() external returns (uint);
    function reserveFactorMantissa() external returns (uint);
    function accrualBlockNumber() external returns (uint);
    function borrowIndex() external returns (uint);
    function totalBorrows() external returns (uint);
    function totalReserves() external returns (uint);
    function totalSupply() external returns (uint);
    function accountTokens(address) external returns (uint);
    function transferAllowances(address,address) external returns (uint);

    function balanceOfUnderlying(address owner) external returns (uint);
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
    function borrowRatePerBlock() external view returns (uint);
    function supplyRatePerBlock() external view returns (uint);
    function totalBorrowsCurrent() external returns (uint);
    function borrowBalanceCurrent(address account) external returns (uint);
    function borrowBalanceStored(address account) external view returns (uint);
    function exchangeRateCurrent() external returns (uint);
    function exchangeRateStored() external view returns (uint);
    function getCash() external view returns (uint);
    function accrueInterest() external returns (uint);
    function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint);

    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    function liquidateBorrow(address borrower, uint repayAmount, CToken cTokenCollateral) external returns (uint);
}