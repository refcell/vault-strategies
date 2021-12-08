// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {Auth} from "solmate/auth/Auth.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// Slimmed Compound Interfaces
import {CToken} from "./interfaces/compound/CToken.sol";
import {ERC20Strategy} from "./interfaces/Strategy.sol";
import {CErc20} from "./interfaces/compound/CErc20.sol";
import {Comptroller} from "./interfaces/compound/Comptroller.sol";

contract CompoundLender is ERC20("Vaults Compound Lending Strategy", "VCLS", 18), ERC20Strategy, Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @dev The cToken to mint for the underlying.
    CErc20 internal immutable CERC20;

    /// @dev COMP token for LP reward harvesting.
    CToken internal immutable COMP;

    /// @dev The Comptroller we want to lever with.
    Comptroller internal immutable TROLL;

    /// @dev The underlying erc20.
    ERC20 internal immutable UNDERLYING;
    uint256 internal immutable BASE_UNIT;

    /// @dev The CErc20 max collateral factor [wad]
    uint256 public cf = 0;

    /// @dev The maximum target collateral factor [wad]
    uint256 public maxf = 0;

    /// @dev The minimum target collateral factor [wad]
    uint256 public minf = 0;

    /// @dev The minimum underlying value to continue iterating.
    uint256 constant DUST = 1e6;

    // CONSTANTS
    uint256 constant WAD = 10 ** 18;

    constructor(
        ERC20 _UNDERLYING,
        CErc20 _CERC20,
        CToken _COMP,
        Comptroller _TROLL,
        Authority _authority
    ) Auth(msg.sender, _authority) {
        UNDERLYING = _UNDERLYING;
        CERC20 = _CERC20;
        COMP = _COMP;
        TROLL = _TROLL;
        BASE_UNIT = 10**_UNDERLYING.decimals();

        // Allow the CToken to spend max uint of underlying.
        // Practically allows unlimited mints and redemptions.
        UNDERLYING.approve(address(CERC20), type(uint256).max);

        // Enter the Comptroller markets to enable CToken as collateral.
        // Docs: https://compound.finance/docs/comptroller#enter-markets
        address[] memory ctokens = new address[](1);
        ctokens[0] = address(_CERC20);
        uint256[] memory errors = new uint256[](1);
        errors = TROLL.enterMarkets(ctokens);
        require(errors[0] == 0, "ENTER_MARKETS_ERRORED");
    }

    /*///////////////////////////////////////////////////////////////
                    STRATEGY ALLOCATE/DEALLOCATE LOGIC
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

        // TODO: leverUp

        emit AllocatedUnderlying(msg.sender, amount);
    }

    /// @notice Emitted when the strategy redeems the CErc20 for the underlying.
    /// @param user The authorized user who triggered the allocation.
    /// @param amount The amount of underlying redeemed.
    event Deallocate(address indexed user, uint256 amount);

    /// @notice Withdraws the amount into the Compound Market.
    /// @param amount The amount of cToken to withdraw.
    function deallocate(uint256 amount) external requiresAuth {
        // TODO: delever if necessary

        // ** Redeem the underlying for the cToken ** //
        CERC20.redeem(amount);

        emit AllocatedUnderlying(msg.sender, amount);
    }

    /*///////////////////////////////////////////////////////////////
                    STRATEGY LEVER/DELEVER LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the Strategy levers up using the CErc20 as collateral.
    /// @param user The authorized user who triggered the lever.
    /// @param amount The amount of underlying to lever borrow.
    event LeveredUp(address indexed user, uint256 indexed amount);

    /// @notice Leverages using the Comptroller.
    /// @dev Enters the Compound Market.
    /// @param amount The amount of cToken to lever.
    function leverUp(uint256 amount) external requiresAuth {
        require(CERC20.balanceOf(address(this)) >= amount, "INSUFFICIENT_FUNDS");

        // NOTE: Comptroller markets are entered in the constructor.

        // TODO: Calculate the borrow amount using the amount
        uint256 borrow_ = amount * cf; // amount of underlying to borrow
        uint256 loops_ = 5; // # rounds of the borrow+mint circuit
        
        require(CERC20.accrueInterest() == 0, "ACCRUED_INTEREST");

        uint256 gems = UNDERLYING.balanceOf(address(this));
        if (gems > 0) {
            require(CERC20.mint(gems) == 0, "UNSUCCESSFUL_CTOKEN_MINT");
        }

        for (uint256 i = 0; i < loops_; i++) {
            uint256 s = CERC20.balanceOfUnderlying(address(this));
            uint256 b = CERC20.borrowBalanceStored(address(this));
            // math overflow if
            //   - b / (s + L) > cf  [insufficient loan to unwind]
            //   - minf > 1e18       [bad configuration]
            //   - minf < u          [can't wind over minf]
            uint256 x1 = ((s * cf) / WAD) - b;
            uint256 x2 = (((((s - amount) * minf) / WAD) - b) * WAD) / (1e18 - minf);
            uint256 max_borrow = min(x1, x2);
            if (max_borrow < DUST) break;
            require(CERC20.borrow(max_borrow) == 0, "FAILED_BORROW");
            require(CERC20.mint(max_borrow) == 0, "FAILED_MINT");
        }
        if (borrow_ > 0) {
            require(CERC20.borrow(borrow_) == 0);
            require(CERC20.mint(borrow_) == 0);
        }

        uint256 u = (CERC20.borrowBalanceStored(address(this)) * WAD) / CERC20.balanceOfUnderlying(address(this));
        require(u < maxf, "FAILED_LEVER_UP");

        emit LeveredUp(msg.sender, amount);
    }

    /// @notice Emitted when the Strategy delevers the CErc20 collateral.
    /// @param user The authorized user who triggered the lever.
    /// @param amount The amount of underlying to delever.
    event Delevered(address indexed user, uint256 indexed amount);

    /// @notice Delever the CErc20 collateral.
    /// @dev Exits the Compound Market.
    /// @param amount The amount of cToken to delever.
    function delever(uint256 amount) external requiresAuth {
        require(CERC20.balanceOf(address(this)) >= amount, "INSUFFICIENT_FUNDS");


        //      |   |   |   |   |   |      //
        //    -------------------------    //
        // ------------------------------- //
        // --- TODO ------------- TODO --- //
        // ---------------  -------------- //
        // --------------    ------------- //
        // --------------    ------------- //
        // ------------------------------- //
        // ------------------------------- //
        // ---------              -------- //
        // ---------     TODO     -------- //
        // ---------              -------- //
        // ------------------------------- //
        //    -------------------------    //
        //              -----              //

        // TODO: Calculate the repay amount using the amount
        uint256 repay_ = amount * cf; // amount of underlying to repay
        uint256 loops_ = 5; // # rounds of the borrow+mint circuit
        uint256 exit_ = 10; // how much underlying to remove following unwind
        uint256 loan_ = 0; // we lend the contract nothing for the tx

        require(CERC20.accrueInterest() == 0, "ACCRUED_INTEREST");

        uint256 u = (CERC20.borrowBalanceStored(address(this)) * WAD) / CERC20.balanceOfUnderlying(address(this));

        require(CERC20.mint(UNDERLYING.balanceOf(address(this))) == 0, "FAILED_MINT");

        for (uint256 i = 0; i < loops_; i++) {
            uint256 s = CERC20.balanceOfUnderlying(address(this));
            uint256 b = CERC20.borrowBalanceStored(address(this));
            // math overflow if
            //   - [insufficient loan to unwind]
            //   - [insufficient loan for exit]
            //   - [bad configuration]
            uint256 x1 = (((s * cf) / WAD - b) * WAD) / cf;
            uint256 x2 = (this.zsub((b + ((exit_ * maxf) / WAD)),
                               ((s - loan_) * maxf) / WAD) * WAD) /
                           (1e18 - maxf);
            uint256 max_repay = min(x1, x2);
            if (max_repay < DUST) break;
            require(CERC20.redeemUnderlying(max_repay) == 0, "FAILED_UNDERLYING_REDEEM");
            require(CERC20.repayBorrow(max_repay) == 0, "FAILED_BORROW_REPAY");
        }
        if (repay_ > 0) {
            require(CERC20.redeemUnderlying(repay_) == 0, "FAILED_UNDERLYING_REDEEM");
            require(CERC20.repayBorrow(repay_) == 0, "FAILED_BORROW_REPAY");
        }
        if (exit_ > 0 || loan_ > 0) {
            require(CERC20.redeemUnderlying(exit_ + loan_) == 0, "FAILED_UNDERLYING_REDEEM");
        }
        if (loan_ > 0) {
            require(UNDERLYING.transfer(msg.sender, loan_), "FAILED_TRANSFER");
        }
        if (exit_ > 0) {
            // TODO: exit?
            // exit(exit_);
        }

        uint256 u_ = (CERC20.borrowBalanceStored(address(this)) * WAD) /
                       CERC20.balanceOfUnderlying(address(this));
        bool ramping = u  <  minf && u_ > u && u_ < maxf;
        bool damping = u  >  maxf && u_ < u && u_ > minf;
        bool tamping = u_ >= minf && u_ <= maxf;
        require(ramping || damping || tamping, "DELEVER_FAILED");

        emit Delevered(msg.sender, amount);
    }


    /// @notice Calculate number blocks until liquidation.
    /// @dev Ignores compound effects, so estimate diverges w.r.t time.
    /// @dev Adapted from https://github.com/Grandthrax/YearnV2-Generic-Lev-Comp-Farm
    function getblocksUntilLiquidation() public view returns (uint256) {
        (, uint256 cfMantissa) = TROLL.markets(address(CERC20));
        /*
            (
                (deposits * collateralThreshold - borrows)
                /
                (borrows * borrowrate - deposits * collateralThreshold * interestrate)
            )
        */
        (uint256 deposits, uint256 borrows) = getCurrentPosition();

        uint256 borrrowRate = CERC20.borrowRatePerBlock();
        uint256 supplyRate = CERC20.supplyRatePerBlock();

        uint256 collateralisedDeposit1 = (deposits * cfMantissa) / 1e18;
        uint256 collateralisedDeposit = collateralisedDeposit1;

        uint256 denom1 = borrows * borrrowRate;
        uint256 denom2 = collateralisedDeposit * supplyRate;

        if (denom2 >= denom1) {
            return type(uint256).max;
        } else {
            uint256 numer = collateralisedDeposit - borrows;
            uint256 denom = denom1 - denom2;
            return (numer * 1e18) / denom; // minus 1 for this block
        }
    }

    /// @notice Calculate the current CToken position.
    /// @dev Fetches balances since last CToken interaction, accrued interest between is absent.
    /// @return deposits The total amount of deposits.
    /// @return borrows The total amount of borrows.
    function getCurrentPosition() public view returns (uint256 deposits, uint256 borrows) {
        (, uint256 ctokenBalance, uint256 borrowBalance, uint256 er) = CERC20.getAccountSnapshot(address(this));
        borrows = borrowBalance;
        deposits = (ctokenBalance * er) / 1e18;
    }

    /*///////////////////////////////////////////////////////////////
                    STRATEGY COLLATERAL FACTOR LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the collateral factors are tuned.
    /// @dev Index all fields due to dense argument distribution.
    /// @param user The authorized user who triggered the allocation.
    /// @param _cf The updated collateral factor.
    /// @param _maxf The updated maximum collateral factor.
    /// @param _minf The updated minimum collateral factor.
    event TunedCollateralFactors(
        address indexed user,
        uint256 _cf,
        uint256 indexed _maxf,
        uint256 indexed _minf
    );

    /// @notice Tunes the maintained collateral factors.
    /// @param _cf The new Collateral Factor.
    /// @param _maxf The new maximum Collateral Factor.
    /// @param _minf The new minimum Collateral Factor.
    function tune(
        uint256 _cf,
        uint256 _maxf,
        uint256 _minf
    ) external requiresAuth {
        cf = _cf;
        maxf = _maxf;
        minf = _minf;

        emit TunedCollateralFactors(msg.sender, cf, maxf, minf);
    }

    /*///////////////////////////////////////////////////////////////
                        FUNCTIONAL STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Harvest COMP rewards.
    function harvest() internal requiresAuth {
        address[] memory ctokens = new address[](1);
        address[] memory users = new address[](1);
        ctokens[0] = address(CERC20);
        users[0] = address(this);
        TROLL.claimComp(users, ctokens, true, true);
    }

    /// @notice Calculates the Net Asset Value of the Strategy.
    /// @return Net Asset Value
    function nav() public returns (uint256) {
        uint256 _nav = UNDERLYING.balanceOf(address(this)) +
            CERC20.balanceOfUnderlying(address(this)) -
            CERC20.borrowBalanceCurrent(address(this));
        return _nav;
    }

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

        // TODO: allocate

        return 0;
    }

    /// @notice Exchanges this token for the underlying.
    /// @param amount The amount of underlying to redeem.
    /// @return 0 on success.
    function redeemUnderlying(uint256 amount) external override returns (uint256) {
        _burn(msg.sender, amount.fdiv(exchangeRate(), BASE_UNIT));

        // TODO: deallocate

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

    /// @dev Helper to find the min of {x,y}
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x <= y ? x : y;
    }

    /// @dev Helper to calculate the zsub of x,y
    function zsub(uint x, uint y) public pure returns (uint z) {
        return x - min(x, y);
    }
}
