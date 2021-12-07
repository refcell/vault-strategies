// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {Auth} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ERC20Strategy} from "./interfaces/Strategy.sol";
import {CToken} from "./interfaces/compound/CToken.sol";
import {Comptroller} from "./interfaces/compound/Comptroller.sol";

contract CompoundLender is ERC20("Vaults Compound Lending Strategy", "VCLS", 18), ERC20Strategy, Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    constructor(ERC20 _UNDERLYING) Auth(Auth(msg.sender).owner(), Auth(msg.sender).authority()) {
        UNDERLYING = _UNDERLYING;

        BASE_UNIT = 10**_UNDERLYING.decimals();
    }

    /*///////////////////////////////////////////////////////////////
                             STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the strategy allocates to Compound.
    /// @param user The authorized user who triggered the allocation.
    /// @param amount The amount of underlying to enter into the compound market.
    event AllocatedUnderlying(address indexed user, uint128 amount);

    /// @notice Allocates the amount into the Compound Market.
    /// @dev Mints the underlying `amount` as a cToken and enters the Compound Market.
    /// @param amount The amount of cToken to mint.
    function allocate(uint256 amount) external requiresAuth {
      // ** Approve cDai to use this DAI ** //
      ERC20(0xF0d0EB522cfa50B716B3b1604C4F0fA6f04376AD).approve(0xF0d0EB522cfa50B716B3b1604C4F0fA6f04376AD, amount);

      // ** Mint cToken for the underlying ** //
      CToken cToken = CToken(0xF0d0EB522cfa50B716B3b1604C4F0fA6f04376AD);
      cToken.mint(amount);

      // ** Enter Markets with the minted cToken ** //
      CToken[] memory tokens = new CToken[](1);
      tokens[0] = cToken;
      Comptroller(0x5eae89dc1c671724a672ff0630122ee834098657).enterMarkets(tokens);

      emit AllocatedUnderlying(msg.sender, amount);
    }

    /// @notice Emitted when the strategy removes liquidity from Compound.
    /// @param user The authorized user who triggered the allocation.
    /// @param amount The amount of underlying withdrawan.
    event WithdrawUnderlying(address indexed user, uint128 amount);

    /// @notice Withdraws the amount into the Compound Market.
    /// @param amount The amount of cToken to withdraw.
    function withdraw(uint256 amount) external requiresAuth {
      // ** Withdraw from the markets ** //
      CToken[] memory tokens = new CToken[](1);
      tokens[0] = CToken(0xF0d0EB522cfa50B716B3b1604C4F0fA6f04376AD);
      Comptroller(0x5eae89dc1c671724a672ff0630122ee834098657).exitMarkets(tokens);

      // ** Redeem the underlying for the cToken ** //
      CToken cToken = CToken(0xF0d0EB522cfa50B716B3b1604C4F0fA6f04376AD);
      cToken.redeem(amount);

      emit AllocatedUnderlying(msg.sender, amount);
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
