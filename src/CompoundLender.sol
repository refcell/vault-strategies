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
    /// @param sender The authorized user who triggered the allocation.
    /// @param amount The amount of underlying to enter into the compound market.
    event AllocatedUnderlying(address indexed user, uint128 amount);

    function allocate(uint256 amount) requireAuth {
      // ** Approve cDai to use this DAI ** //
      ERC20(0xf0d0eb522cfa50b716b3b1604c4f0fa6f04376ad).approve(0xf0d0eb522cfa50b716b3b1604c4f0fa6f04376ad, amount);

      // ** Mint cToken for the underlying ** //
      CToken cToken = CToken(0xf0d0eb522cfa50b716b3b1604c4f0fa6f04376ad);
      cToken.mint(amount);

      // ** Enter Markets with the minted cToken ** //
      CTokens[] memory tokens = new CTokens[](1);
      tokens[0] = cToken;
      Comptroller(0x5eae89dc1c671724a672ff0630122ee834098657).enterMarkets(tokens);

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