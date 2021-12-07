// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {Auth} from "solmate/auth/Auth.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// Slimmed Compound Interfaces
import {ERC20Strategy} from "./interfaces/Strategy.sol";
import {CErc20} from "./interfaces/compound/CErc20.sol";
import {Comptroller} from "./interfaces/compound/Comptroller.sol";

contract CompoundLender is ERC20("Vaults Compound Lending Strategy", "VCLS", 18), ERC20Strategy, Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @dev the cToken to mint for the underlying
    CErc20 internal immutable CERC20;

    /// @dev the underlying token
    ERC20 internal immutable UNDERLYING;

    /// @dev the erc20 base unit
    uint256 internal immutable BASE_UNIT;

    constructor(
        ERC20 _UNDERLYING,
        CErc20 _CERC20,
        Authority _authority
    ) Auth(msg.sender, _authority) {
        UNDERLYING = _UNDERLYING;
        CERC20 = _CERC20;
        BASE_UNIT = 10**_UNDERLYING.decimals();
    }

    /*///////////////////////////////////////////////////////////////
                            CUSTOM STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the strategy mints CErc20 using the underlying.
    /// @param user The authorized user who triggered the allocation.
    /// @param amount The amount of underlying to mint.
    event AllocatedUnderlying(address indexed user, uint256 amount);

    /// @notice Allocates the underlying to Compound.
    /// @dev Mints the underlying `amount` as a cToken.
    /// @param amount The amount of cToken to mint.
    function allocate(uint256 amount) external requiresAuth {
        // ** Approve cDai to use the underlying ** //
        UNDERLYING.approve(address(CERC20), amount);

        // ** Mint cToken for the underlying ** //
        CERC20.mint(amount);

        emit AllocatedUnderlying(msg.sender, amount);
    }

    /// @notice Emitted when the Strategy levers up using the CErc20 as collateral.
    /// @param user The authorized user who triggered the lever.
    /// @param amount The amount of underlying to lever borrow.
    event LeveredUp(address indexed user, uint256 amount);

    /// @notice Leverages using the Comptroller.
    /// @dev Enters the Compound Market.
    /// @param amount The amount of cToken to lever.
    function leverUp(uint256 amount) external requiresAuth {
        require(CERC20.balanceOf(address(this)) >= amount, "INSUFFICIENT_FUNDS");

        // ** Enter Markets with the minted cToken ** //
        //   address[] memory tokens = new address[](1);
        //   tokens[0] = address(CERC20);
        // TODO: somehow call ComptrollerKovan at 0xeA7ab3528efD614f4184d1D223c91993344e6A9e as proxy
        //   Comptroller(0x5eAe89DC1C671724A672ff0630122ee834098657).enterMarkets(tokens);
        //   Comptroller(0xeA7ab3528efD614f4184d1D223c91993344e6A9e).enterMarkets(tokens);

        emit LeveredUp(msg.sender, amount);
    }

    /// @notice Emitted when the Strategy delevers the CErc20 collateral.
    /// @param user The authorized user who triggered the lever.
    /// @param amount The amount of underlying to delever.
    event Delevered(address indexed user, uint256 amount);

    /// @notice Delever the CErc20 collateral.
    /// @dev Exits the Compound Market.
    /// @param amount The amount of cToken to delever.
    function delever(uint256 amount) external requiresAuth {
        require(CERC20.balanceOf(address(this)) >= amount, "INSUFFICIENT_FUNDS");

        // ** Withdraw from the markets ** //
        Comptroller(0x5eAe89DC1C671724A672ff0630122ee834098657).exitMarket(address(CERC20));

        emit AllocatedUnderlying(msg.sender, amount);
    }

    /// @notice Emitted when the strategy redeems the CErc20 for the underlying.
    /// @param user The authorized user who triggered the allocation.
    /// @param amount The amount of underlying redeemed.
    event Deallocate(address indexed user, uint256 amount);

    /// @notice Withdraws the amount into the Compound Market.
    /// @param amount The amount of cToken to withdraw.
    function deallocate(uint256 amount) external requiresAuth {
        // ** Redeem the underlying for the cToken ** //
        CERC20.redeem(amount);

        emit AllocatedUnderlying(msg.sender, amount);
    }

    /*///////////////////////////////////////////////////////////////
                        BASE STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/  

    /// @notice Required Strategy function for CEther.
    function isCEther() external pure override returns (bool) {
        return false;
    }

    /// @notice Visibility for the underlying token.
    function underlying() external view override returns (ERC20) {
        return UNDERLYING;
    }

    /// @notice Visibility for the CErc20 (CToken).
    function cerc20() external view returns (CErc20) {
        return CERC20;
    }

    /// @notice Mints VCLS in exchange for underlying.
    /// @param amount The amount of underlying to mint VCLS for.
    /// @return 0 on success.
    function mint(uint256 amount) external override returns (uint256) {
        _mint(msg.sender, amount.fdiv(exchangeRate(), BASE_UNIT));

        UNDERLYING.safeTransferFrom(msg.sender, address(this), amount);

        return 0;
    }

    /// @notice Exchanges this token for the underlying.
    /// @param amount The amount of underlying to redeem.
    /// @return 0 on success.
    function redeemUnderlying(uint256 amount) external override returns (uint256) {
        _burn(msg.sender, amount.fdiv(exchangeRate(), BASE_UNIT));

        UNDERLYING.safeTransfer(msg.sender, amount);

        return 0;
    }

    /// @notice Fetches the user's underlying balance.
    /// @param user The user's address to check their balance for.
    /// @return The user's underlying balance.
    function balanceOfUnderlying(address user) external view override returns (uint256) {
        return balanceOf[user].fmul(exchangeRate(), BASE_UNIT);
    }

    /// @notice Calculates the echange rate to the underlying.
    /// @return The exchange rate from VCLS to the underlying.
    function exchangeRate() internal view returns (uint256) {
        uint256 cTokenSupply = totalSupply;

        if (cTokenSupply == 0) return BASE_UNIT;

        return UNDERLYING.balanceOf(address(this)).fdiv(cTokenSupply, BASE_UNIT);
    }
}
