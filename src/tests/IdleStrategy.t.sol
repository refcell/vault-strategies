// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "../IdleStrategy.sol";

contract IdleStrategyTest is DSTest {
    IdleStrategy idle;

    function setUp() public {
        idle = new IdleStrategy();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
