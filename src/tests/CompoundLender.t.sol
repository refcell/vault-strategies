// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import {Authority} from "solmate/auth/Auth.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Vault} from "vaults/Vault.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {VaultFactory} from "vaults/VaultFactory.sol";

import {Strategy} from "vaults/interfaces/Strategy.sol";
import {CompoundLender} from "../CompoundLender.sol";
import {CErc20} from "../interfaces/compound/CErc20.sol";
import {Comptroller} from "../interfaces/compound/Comptroller.sol";
import {CToken} from "../interfaces/compound/CToken.sol";

contract CompoundLenderTest is DSTestPlus {
    CompoundLender strategy;
    MockERC20 underlying;
    VaultFactory vaultFactory;
    Vault vault;
    CErc20 cErc20;
    Comptroller troll;
    CToken comp;

    function setUp() public {
        underlying = new MockERC20("Mock Token", "TKN", 18);
        vaultFactory = new VaultFactory(address(this), Authority(address(0)));
        vault = vaultFactory.deployVault(underlying);

        vault.setFeePercent(0.1e18);
        vault.setHarvestDelay(6 hours);
        vault.setHarvestWindow(5 minutes);
        vault.setTargetFloatPercent(0.01e18);

        vault.initialize();

        // cDai
        cErc20 = CErc20(0xF0d0EB522cfa50B716B3b1604C4F0fA6f04376AD);

        // cDai comptroller
        troll = Comptroller(0x5eAe89DC1C671724A672ff0630122ee834098657);

        // COMP gov token
        comp = CToken(0x61460874a7196d6a22D1eE4922473664b3E95270);

        strategy = new CompoundLender(underlying, cErc20, comp, troll, Authority(address(0)));
    }

    /*///////////////////////////////////////////////////////////////
                     STRATEGY DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testAtomicEnterExitSinglePool() public {
        underlying.mint(address(this), 1e18);
        underlying.approve(address(vault), 1e18);
        vault.deposit(1e18);

        vault.trustStrategy(Strategy(address(strategy)));

        vault.depositIntoStrategy(Strategy(address(strategy)), 1e18);

        assertEq(vault.exchangeRate(), 1e18);
        assertEq(vault.totalStrategyHoldings(), 1e18);
        assertEq(vault.totalHoldings(), 1e18);
        assertEq(vault.totalFloat(), 0);
        assertEq(vault.balanceOf(address(this)), 1e18);
        assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

        vault.withdrawFromStrategy(Strategy(address(strategy)), 0.5e18);

        assertEq(vault.exchangeRate(), 1e18);
        assertEq(vault.totalStrategyHoldings(), 0.5e18);
        assertEq(vault.totalHoldings(), 1e18);
        assertEq(vault.totalFloat(), 0.5e18);
        assertEq(vault.balanceOf(address(this)), 1e18);
        assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

        vault.withdrawFromStrategy(Strategy(address(strategy)), 0.5e18);

        assertEq(vault.exchangeRate(), 1e18);
        assertEq(vault.totalStrategyHoldings(), 0);
        assertEq(vault.totalHoldings(), 1e18);
        assertEq(vault.totalFloat(), 1e18);
        assertEq(vault.balanceOf(address(this)), 1e18);
        assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
    }

    /// @dev enter mock uniswap pool
    function testProfitableCompoundMarkets() public {
        // ** Deposit underlying into vault ** //
        underlying.mint(address(this), 1.5e18);
        underlying.approve(address(vault), 1e18);
        vault.deposit(1e18);

        // ** Deposit underlying into strategy ** //
        vault.trustStrategy(Strategy(address(strategy)));
        vault.depositIntoStrategy(Strategy(address(strategy)), 1e18);
        vault.pushToWithdrawalQueue(Strategy(address(strategy)));

        // ** Deposit into Compound ** //
        strategy.allocate(10e18);

        // ** Harvest the strategy ** //
        Strategy[] memory strategiesToHarvest = new Strategy[](1);
        strategiesToHarvest[0] = Strategy(address(strategy));
        vault.harvest(strategiesToHarvest);

        // ** Vault Sanity Checks ** //
        assertEq(vault.totalStrategyHoldings(), 1.5e18);
        assertEq(vault.balanceOf(address(this)), 1e18);
        assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

        hevm.warp(block.timestamp + vault.harvestDelay());

        // ** Withdraw from Compound ** //
        strategy.deallocate(10e18);

        // ** Mock interest by sending the strategy mula ** //
        underlying.transfer(address(strategy), 0.5e18);

        // ** Redeem the underlying from the vault ** //
        vault.redeem(1e18);

        // ** Sanity Checks ** //
        assertEq(underlying.balanceOf(address(this)), 1428571428571428571);
        assertEq(vault.totalStrategyHoldings(), 70714285714285715);
        assertEq(vault.balanceOfUnderlying(address(vault)), 71428571428571429);
    }
}
