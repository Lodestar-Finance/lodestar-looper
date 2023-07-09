// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILoopy {
    struct UserData {
        address user;
        uint256 tokenAmount;
        IERC20 borrowedToken;
        uint256 borrowedAmount;
        IERC20 tokenToLoop;
    }

    error UNAUTHORIZED(string);
    error INVALID_LEVERAGE();
    error INVALID_APPROVAL();
    error FAILED(string);
}

interface IGlpDepositor {
    function deposit(uint256 _amount) external;

    function redeem(uint256 _amount) external;

    function donate(uint256 _assets) external;
}

interface IRewardRouterV2 {
    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256);
}

interface ICERC20Update {
    function borrowBehalf(uint256 borrowAmount, address borrowee) external returns (uint256);
}

interface ICERC20 is IERC20, ICERC20Update {
    // CToken
    /**
     * @notice Get the underlying balance of the `owner`
     * @dev This also accrues interest in a transaction
     * @param owner The address of the account to query
     * @return The amount of underlying owned by `owner`
     */
    function balanceOfUnderlying(address owner) external returns (uint256);

    /**
     * @notice Returns the current per-block borrow interest rate for this cToken
     * @return The borrow interest rate per block, scaled by 1e18
     */
    function borrowRatePerBlock() external view returns (uint256);

    /**
     * @notice Returns the current per-block supply interest rate for this cToken
     * @return The supply interest rate per block, scaled by 1e18
     */
    function supplyRatePerBlock() external view returns (uint256);

    /**
     * @notice Accrue interest then return the up-to-date exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() external returns (uint256);

    // Cerc20
    function mint(uint256 mintAmount) external returns (uint256);
}

interface IPriceOracleProxyETH {
    function getUnderlyingPrice(address cToken) external view returns (uint256);
}

// 6/26/2023: https://docs.balancer.fi/reference/contracts/deployment-addresses/mainnet.html#gauges-and-governance
interface IProtocolFeesCollector {
    function getFlashLoanFeePercentage() external view returns (uint256);
}

interface IGlpOracleInterface {
    function getGLPPrice() external view returns (uint256);

    function getPlvGLPPrice() external view returns (uint256);
}

interface IUnitrollerInterface {
    function getAccountLiquidity(address account) external view returns (uint256, uint256, uint256);

    function getHypotheticalAccountLiquidity(
        address account,
        address cTokenModify,
        uint256 redeemTokens,
        uint256 borrowTokens
    ) external view returns (uint256, uint256, uint256);
}

interface SushiRouterInterface {
    function WETH() external returns (address);

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        fixed swapAmountETH,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external;
}
