// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import {Authority} from "solmate/auth/Auth.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Vault} from "vaults/Vault.sol";
import {VaultFactory} from "vaults/VaultFactory.sol";

import {UniswapV2LP} from "../UniswapV2LP.sol";

import {Strategy} from "vaults/interfaces/Strategy.sol";


contract UniswapV2LPTest is DSTestPlus {
    UniswapV2LP strategy;
    MockERC20 underlying;
    VaultFactory vaultFactory;
    Vault vault;

    function setUp() public {
        underlying = new MockERC20("Mock Token", "TKN", 18);
        vaultFactory = new VaultFactory(address(this), Authority(address(0)));
        vault = vaultFactory.deployVault(underlying);

        vault.setFeePercent(0.1e18);
        vault.setHarvestDelay(6 hours);
        vault.setHarvestWindow(5 minutes);
        vault.setTargetFloatPercent(0.01e18);

        vault.initialize();

        strategy = new UniswapV2LP(underlying);
    }

    /*///////////////////////////////////////////////////////////////
                     STRATEGY DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testAtomicEnterExitSinglePool() public {
        underlying.mint(address(this), 1e18);
        underlying.approve(address(vault), 1e18);
        vault.deposit(1e18);

        vault.trustStrategy(strategy);

        vault.depositIntoStrategy(strategy, 1e18);

        assertEq(vault.exchangeRate(), 1e18);
        assertEq(vault.totalStrategyHoldings(), 1e18);
        assertEq(vault.totalHoldings(), 1e18);
        assertEq(vault.totalFloat(), 0);
        assertEq(vault.balanceOf(address(this)), 1e18);
        assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

        vault.withdrawFromStrategy(strategy, 0.5e18);

        assertEq(vault.exchangeRate(), 1e18);
        assertEq(vault.totalStrategyHoldings(), 0.5e18);
        assertEq(vault.totalHoldings(), 1e18);
        assertEq(vault.totalFloat(), 0.5e18);
        assertEq(vault.balanceOf(address(this)), 1e18);
        assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

        vault.withdrawFromStrategy(strategy, 0.5e18);

        assertEq(vault.exchangeRate(), 1e18);
        assertEq(vault.totalStrategyHoldings(), 0);
        assertEq(vault.totalHoldings(), 1e18);
        assertEq(vault.totalFloat(), 1e18);
        assertEq(vault.balanceOf(address(this)), 1e18);
        assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
    }

    /// @dev enter mock uniswap pool
    function testProfitableUniswapPool() public {
        // ** Deposit underlying into vault ** //
        underlying.mint(address(this), 1.5e18);
        underlying.approve(address(vault), 1e18);
        vault.deposit(1e18);

        // ** Deposit underlying into strategy ** //
        vault.trustStrategy(strategy);
        vault.depositIntoStrategy(strategy, 1e18);
        vault.pushToWithdrawalQueue(strategy);

        // ** Mock interest by sending underlying to the uniswap pool as a fee ** //
        underlying.transfer(address(0x0), 0.5e18);

        // ** Harvest the strategy ** //
        Strategy[] memory strategiesToHarvest = new Strategy[](1);
        strategiesToHarvest[0] = strategy;
        vault.harvest(strategiesToHarvest);

        uint256 startingTimestamp = block.timestamp;

        // ** Vault Sanity Checks ** //
        assertEq(vault.lastHarvest(), startingTimestamp);
        assertEq(vault.lastHarvestWindowStart(), startingTimestamp);
        assertEq(vault.totalStrategyHoldings(), 1.5e18);
        assertEq(vault.balanceOf(address(this)), 1e18);
        assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

        hevm.warp(block.timestamp + vault.harvestDelay());

        vault.redeem(1e18);

        assertEq(underlying.balanceOf(address(this)), 1428571428571428571);

        assertEq(vault.exchangeRate(), 1428571428571428580);
        assertEq(vault.totalStrategyHoldings(), 70714285714285715);
        assertEq(vault.totalFloat(), 714285714285714);
        assertEq(vault.totalHoldings(), 71428571428571429);
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(vault.balanceOfUnderlying(address(this)), 0);
        assertEq(vault.totalSupply(), 0.05e18);
        assertEq(vault.balanceOf(address(vault)), 0.05e18);
        assertEq(vault.balanceOfUnderlying(address(vault)), 71428571428571429);
    }
}
