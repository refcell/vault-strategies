// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "ds-test/test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "../IdleStrategy.sol";

contract IdleStrategyTest is DSTest {
    IdleStrategy idle;
    MockERC20 underlying;
    function setUp() public {
        underlying = new MockERC20("Mock Token", "TKN", 18);

        idle = new IdleStrategy(underlying);
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
