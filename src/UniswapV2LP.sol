// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {Authority} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Auth} from "solmate/auth/Auth.sol";

import {ERC20Strategy} from "./interfaces/Strategy.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";

contract UniswapV2LP is ERC20("Vaults Uniswap LP Strategy", "VULP", 18), ERC20Strategy, Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @dev UniswapV2Router02 for DAI<>RAI at a 3% fee
    /// @dev https://kovan.etherscan.io/address/0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    constructor(ERC20 _UNDERLYING, Authority _authority) Auth(msg.sender, _authority) {
        UNDERLYING = _UNDERLYING;

        BASE_UNIT = 10**_UNDERLYING.decimals();
    }


    /*///////////////////////////////////////////////////////////////
                             STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/


    function allocate() external requiresAuth {
        /*
            addLiquidity(
                tokenA (address),
                tokenB (address),
                amountADesired (uint256),
                amountBDesired (uint256),
                amountAMin (uint256),
                amountBMin (uint256),
                to (address),
                deadline (uint256)
            )
        */
        // router.addLiquidity(
        //     UNDERLYING, // RAI
        //     0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa, // DAI
        //     0,
        //     0,
        //     0,
        //     0,
        //     address(this)
        // );
    }

    function isCEther() external pure override returns (bool) {
        return false;
    }

    function underlying() external view override returns (ERC20) {
        return UNDERLYING;
    }

    function mint(uint256 amount) external override returns (uint256) {
        _mint(msg.sender, amount.fdiv(exchangeRate(), BASE_UNIT));

        UNDERLYING.safeTransferFrom(msg.sender, address(this), amount);

        return 0;
    }

    function redeemUnderlying(uint256 amount) external override returns (uint256) {
        _burn(msg.sender, amount.fdiv(exchangeRate(), BASE_UNIT));

        UNDERLYING.safeTransfer(msg.sender, amount);

        return 0;
    }

    function balanceOfUnderlying(address user) external view override returns (uint256) {
        return balanceOf[user].fmul(exchangeRate(), BASE_UNIT);
    }

  
    /*///////////////////////////////////////////////////////////////
                            INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    ERC20 internal immutable UNDERLYING;

    uint256 internal immutable BASE_UNIT;

    function exchangeRate() internal view returns (uint256) {
        uint256 cTokenSupply = totalSupply;

        if (cTokenSupply == 0) return BASE_UNIT;

        return UNDERLYING.balanceOf(address(this)).fdiv(cTokenSupply, BASE_UNIT);
    }
}
