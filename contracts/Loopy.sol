// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IFlashLoanRecipient.sol";
import "./LoopyConstants.sol";
import "./utils/Swap.sol";

contract Loopy is ILoopy, LoopyConstants, Swap, Ownable2Step, IFlashLoanRecipient, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // add mapping of token addresses to their decimal places
    mapping(IERC20 => uint8) public decimals;
    // add mapping to store the allowed tokens. Mapping provides faster access than array
    mapping(IERC20 => bool) public allowedTokens;
    // add mapping to store lToken contracts
    mapping(IERC20 => ICERC20) private lTokenMapping;
    // add mapping to store lToken collateral factors
    mapping(IERC20 => uint64) private collateralFactor;

    constructor() {
        // initialize decimals for each token
        decimals[USDC_NATIVE] = 6;
        decimals[USDT] = 6;
        decimals[WBTC] = 8;
        decimals[DAI] = 18;
        decimals[FRAX] = 18;
        decimals[ARB] = 18;
        decimals[PLVGLP] = 18;

        // set the allowed tokens in the constructor
        // we can add/remove these with owner functions later
        allowedTokens[USDC_NATIVE] = true;
        allowedTokens[USDT] = true;
        allowedTokens[WBTC] = true;
        allowedTokens[DAI] = true;
        allowedTokens[FRAX] = true;
        allowedTokens[ARB] = true;
        allowedTokens[PLVGLP] = true;

        // map tokens to lTokens
        lTokenMapping[USDC_NATIVE] = lUSDC;
        lTokenMapping[USDT] = lUSDT;
        lTokenMapping[WBTC] = lWBTC;
        lTokenMapping[DAI] = lDAI;
        lTokenMapping[FRAX] = lFRAX;
        lTokenMapping[ARB] = lARB;
        lTokenMapping[PLVGLP] = lPLVGLP;

        // map lTokens to collateralFactors
        collateralFactor[USDC_NATIVE] = 820000000000000000;
        collateralFactor[USDT] = 700000000000000000;
        collateralFactor[WBTC] = 750000000000000000;
        collateralFactor[DAI] = 750000000000000000;
        collateralFactor[FRAX] = 750000000000000000;
        collateralFactor[ARB] = 700000000000000000;
        collateralFactor[PLVGLP] = 750000000000000000;

        // approve glp contracts to spend USDC for minting GLP
        USDC_BRIDGED.approve(address(REWARD_ROUTER_V2), type(uint256).max);
        USDC_BRIDGED.approve(address(GLP), type(uint256).max);
        USDC_BRIDGED.approve(address(GLP_MANAGER), type(uint256).max);
        // approve GlpDepositor to spend GLP for minting plvGLP
        sGLP.approve(address(GLP_DEPOSITOR), type(uint256).max);
        GLP.approve(address(GLP_DEPOSITOR), type(uint256).max);
        sGLP.approve(address(REWARD_ROUTER_V2), type(uint256).max);
        GLP.approve(address(REWARD_ROUTER_V2), type(uint256).max);
        // approve balancer vault
        USDC_BRIDGED.approve(address(VAULT), type(uint256).max);
        USDT.approve(address(VAULT), type(uint256).max);
        WBTC.approve(address(VAULT), type(uint256).max);
        DAI.approve(address(VAULT), type(uint256).max);
        FRAX.approve(address(VAULT), type(uint256).max);
        ARB.approve(address(VAULT), type(uint256).max);
        // approve lTokens to be minted using underlying
        PLVGLP.approve(address(lPLVGLP), type(uint256).max);
        USDC_NATIVE.approve(address(lUSDC), type(uint256).max);
        USDT.approve(address(lUSDT), type(uint256).max);
        WBTC.approve(address(lWBTC), type(uint256).max);
        DAI.approve(address(lDAI), type(uint256).max);
        FRAX.approve(address(lFRAX), type(uint256).max);
        ARB.approve(address(lARB), type(uint256).max);
        // approve uni router for native USDC swap
        USDC_NATIVE.approve(address(UNI_ROUTER), type(uint256).max);
    }

    // declare events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Loan(uint256 value);
    event BalanceOf(uint256 balanceAmount, uint256 loanAmount);
    event Allowance(uint256 allowance, uint256 loanAmount);
    event UserDataEvent(
        address indexed from,
        uint256 tokenAmount,
        address borrowedToken,
        uint256 borrowedAmount,
        address tokenToLoop
    );
    event plvGLPBalance(uint256 balanceAmount);
    event lTokenBalance(uint256 balanceAmount);
    event Received(address, uint);
    event BalancerFeeAmount(uint256 amount);

    function addToken(IERC20 tokenAddress, uint8 tokenDecimals, ICERC20 lTokenAddress) external onlyOwner {
        require(!allowedTokens[tokenAddress], "token already allowed");
        allowedTokens[tokenAddress] = true;

        // create our IERC20 object and map it accordingly
        ICERC20 _lTokenSymbol = ICERC20(lTokenAddress);
        decimals[tokenAddress] = tokenDecimals;
        lTokenMapping[tokenAddress] = _lTokenSymbol;

        // approve balance vault and the lToken market to be able to spend the newly added underlying
        tokenAddress.approve(address(VAULT), type(uint256).max);
        tokenAddress.approve(address(_lTokenSymbol), type(uint256).max);
    }

    function removeToken(IERC20 tokenAddress) external onlyOwner {
        require(allowedTokens[tokenAddress], "token not allowed");
        allowedTokens[tokenAddress] = false;

        // nullify, essentially, existing records
        delete decimals[tokenAddress];
        delete lTokenMapping[tokenAddress];
    }

    function mockLoop(IERC20 _token, uint256 _amount, uint16 _leverage, address _user) external view returns (uint256) {
        {
            uint256 hypotheticalSupply;
            uint256 decimalScale;
            uint256 decimalExp;
            uint256 tokenDecimals;
            uint256 price;

            (uint256 loanAmount, IERC20 tokenToBorrow) = getNotionalLoanAmountIn1e18(_token, _amount, _leverage);

            // mock a hypothetical borrow to see what state it puts the account in (before factoring in our new liquidity)
            (, uint256 hypotheticalLiquidity, uint256 hypotheticalShortfall) = UNITROLLER
                .getHypotheticalAccountLiquidity(_user, address(lTokenMapping[tokenToBorrow]), 0, loanAmount);

            // if the account is still healthy without factoring in our newly supplied balance, we know for a fact they can support this operation.
            // so let's just return now and not waste any more time
            if (hypotheticalLiquidity > 0) {
                return 0; // pass
            } else {
                // otherwise, lets do some maths
                // lets get our hypotheticalSupply and and see if it's greater than our hypotheticalShortfall. if it is, we know the account can support this operation
                if (_token == PLVGLP) {
                    uint256 plvGLPPriceInEth = PLVGLP_ORACLE.getPlvGLPPrice();
                    tokenDecimals = (10 ** (decimals[PLVGLP]));
                    hypotheticalSupply =
                        (plvGLPPriceInEth * (loanAmount * (collateralFactor[PLVGLP] / 1e18))) /
                        tokenDecimals;
                } else {
                    // tokenToBorrow == _token in every instance that doesn't involve plvGLP (which borrows USDC)
                    uint256 tokenPriceInEth = PRICE_ORACLE.getUnderlyingPrice(address(lTokenMapping[tokenToBorrow]));
                    decimalScale = 18 - decimals[tokenToBorrow];
                    decimalExp = (10 ** decimalScale);
                    price = tokenPriceInEth / decimalExp;
                    tokenDecimals = (10 ** (decimals[tokenToBorrow]));
                    hypotheticalSupply =
                        (price * (loanAmount * (collateralFactor[tokenToBorrow] / 1e18))) /
                        tokenDecimals;
                }

                if (hypotheticalSupply > hypotheticalShortfall) {
                    return 0; // pass
                } else {
                    return 1; // fail
                }
            }
        }
    }

    // allows users to loop to a desired leverage, within our pre-set ranges
    function loop(IERC20 _token, uint256 _amount, uint16 _leverage, uint16 _useWalletBalance) external {
        require(allowedTokens[_token], "token not allowed to loop");
        require(tx.origin == msg.sender, "not an EOA");
        require(_amount > 0, "amount must be greater than 0");
        require(
            _leverage >= DIVISOR && _leverage <= MAX_LEVERAGE,
            "invalid leverage, range must be between DIVISOR and MAX_LEVERAGE values"
        );

        // mock loop when the user wants to use their existing lodestar balance.
        // if it fails we know the account cannot loop in the current state they are in
        if (_useWalletBalance == 0 && _token != PLVGLP) {
            uint256 shortfall = this.mockLoop(_token, _amount, _leverage, msg.sender);
            require(
                shortfall == 0,
                "Existing balance on Lodestar unable to support operation. Please consider increasing your supply balance first."
            );
        }

        if (_useWalletBalance == 0 && _token == PLVGLP) {
            uint256 amountPlusSlippage = (_amount * 101) / 100;
            uint256 shortfall = this.mockLoop(_token, amountPlusSlippage, _leverage, msg.sender);
            require(
                shortfall == 0,
                "Existing balance on Lodestar unable to support operation. Please consider increasing your supply balance first."
            );
        }

        // if the user wants us to mint using their existing wallet balance (indiciated with 1), then do so.
        // otherwise, read their existing balance and flash loan to increase their position
        if (_useWalletBalance == 1) {
            // transfer tokens to this contract so we can mint in 1 go.
            _token.safeTransferFrom(msg.sender, address(this), _amount);
            emit Transfer(msg.sender, address(this), _amount);
        }

        uint256 loanAmount;
        IERC20 tokenToBorrow;

        (loanAmount, tokenToBorrow) = getNotionalLoanAmountIn1e18(_token, _amount, _leverage);

        if (tokenToBorrow.balanceOf(address(BALANCER_VAULT)) < loanAmount)
            revert FAILED("balancer vault token balance < loan");
        emit BalanceOf(tokenToBorrow.balanceOf(address(BALANCER_VAULT)), loanAmount);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = tokenToBorrow;

        uint256[] memory loanAmounts = new uint256[](1);
        loanAmounts[0] = loanAmount;

        UserData memory userData = UserData({
            user: msg.sender,
            tokenAmount: _amount,
            borrowedToken: tokenToBorrow,
            borrowedAmount: loanAmount,
            tokenToLoop: _token
        });
        emit UserDataEvent(msg.sender, _amount, address(tokenToBorrow), loanAmount, address(_token));

        BALANCER_VAULT.flashLoan(IFlashLoanRecipient(this), tokens, loanAmounts, abi.encode(userData));
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override nonReentrant {
        if (msg.sender != address(BALANCER_VAULT)) revert UNAUTHORIZED("balancer vault is not the sender");

        UserData memory data = abi.decode(userData, (UserData));

        // ensure the transaction is user originated
        if (tx.origin != data.user) revert UNAUTHORIZED("user did not originate transaction");

        // ensure we borrowed the proper amounts
        if (data.borrowedAmount != amounts[0] || data.borrowedToken != tokens[0])
            revert FAILED("borrowed amounts and/or borrowed tokens do not match initially set values");

        // sanity check: emit whenever the fee for balancer is greater than 0 for tracking purposes
        if (feeAmounts[0] > 0) {
            emit BalancerFeeAmount(feeAmounts[0]);
        }

        // account for some plvGLP specific logic
        if (data.tokenToLoop == PLVGLP) {
            uint256 nominalSlippage = 5e16; // 5% slippage tolerance
            uint256 glpPrice = getGLPPrice(); // returns in 1e18
            uint256 minumumExpectedUSDCSwapAmount = (data.borrowedAmount) * (1e18 - nominalSlippage);
            uint256 minimumExpectedGlpSwapAmount = (minumumExpectedUSDCSwapAmount / (glpPrice / 1e18)) / 1e6;

            // mint GLP. approval needed
            uint256 glpAmount = REWARD_ROUTER_V2.mintAndStakeGlp(
                address(data.borrowedToken), // the token to buy GLP with
                data.borrowedAmount, // the amount of token to use for the purchase
                0, // the minimum acceptable USD value of the GLP purchased
                minimumExpectedGlpSwapAmount // the minimum acceptible GLP amount
            );
            if (glpAmount == 0) revert FAILED("glp=0");
            if (glpAmount < minimumExpectedGlpSwapAmount)
                revert FAILED("glp amount returned less than minumum expected swap amount");

            // TODO whitelist this contract for plvGLP mint
            // mint plvGLP. approval needed
            uint256 _oldPlvglpBal = PLVGLP.balanceOf(address(this));
            GLP_DEPOSITOR.deposit(glpAmount);

            // check new balances and confirm we properly minted
            uint256 _newPlvglpBal = PLVGLP.balanceOf(address(this));
            emit plvGLPBalance(_newPlvglpBal);
            require(_newPlvglpBal > _oldPlvglpBal, "glp deposit failed, new balance < old balance");
        }

        uint256 _finalBal;

        // mint our respective token by depositing it into Lodestar's respective lToken contract (approval needed)
        unchecked {
            // if we are in the native usdc loop flow, let's make sure we swap our borrowed bridged usdc from balancer for native usdc before minting
            if (data.tokenToLoop == USDC_NATIVE) {
                uint256 bridgedUSDCBalance = USDC_BRIDGED.balanceOf(address(this));
                Swap.swapThroughUniswap(
                    address(USDC_BRIDGED),
                    address(USDC_NATIVE),
                    bridgedUSDCBalance,
                    data.borrowedAmount
                );
                // transfer remaining bridged USDC back to the user
                uint256 remainingBridgedUSDCBalance = USDC_BRIDGED.balanceOf(address(this));
                USDC_BRIDGED.safeTransferFrom(address(this), data.user, remainingBridgedUSDCBalance);
            }
            lTokenMapping[data.tokenToLoop].mint(data.tokenToLoop.balanceOf(address(this)));
            lTokenMapping[data.tokenToLoop].transfer(
                data.user,
                lTokenMapping[data.tokenToLoop].balanceOf(address(this))
            );
            _finalBal = lTokenMapping[data.tokenToLoop].balanceOf(address(this));

            emit lTokenBalance(_finalBal);
            require(_finalBal == 0, "lToken balance not 0 at the end of loop");
        }

        uint256 baseBorrowAmount;
        uint256 repayAmountFactoringInFeeAmount;

        // factor in any balancer fees into the overall loan amount we wish to borrow
        uint256 currentBalancerFeePercentage = BALANCER_PROTOCOL_FEES_COLLECTOR.getFlashLoanFeePercentage();
        uint256 currentBalancerFeeAmount = (data.borrowedAmount * currentBalancerFeePercentage) / 1e18;

        //if the loop token is plvGLP or native USDC, we need to borrow a little more to account for fees/slippage on the swap back to bridged USDC
        if (data.tokenToLoop == PLVGLP || data.tokenToLoop == USDC_NATIVE) {
            baseBorrowAmount = (data.borrowedAmount * 101) / 100;
            repayAmountFactoringInFeeAmount = baseBorrowAmount + currentBalancerFeeAmount;
        } else {
            repayAmountFactoringInFeeAmount = data.borrowedAmount + currentBalancerFeeAmount;
        }

        emit Loan(repayAmountFactoringInFeeAmount);

        if (data.tokenToLoop == PLVGLP || data.tokenToLoop == USDC_NATIVE) {
            // plvGLP requires us to repay the loan with USDC
            lUSDC.borrowBehalf(repayAmountFactoringInFeeAmount, data.user);
            // transfer native USDC back into the contract after borrowing bridged USDC
            USDC_NATIVE.safeTransferFrom(msg.sender, address(this), repayAmountFactoringInFeeAmount);
            emit Transfer(msg.sender, address(this), repayAmountFactoringInFeeAmount);
            // we need to swap our native USDC for bridged USDC to repay the loan
            uint256 nativeUSDCBalance = USDC_NATIVE.balanceOf(address(this));
            Swap.swapThroughUniswap(
                address(USDC_NATIVE),
                address(USDC_BRIDGED),
                nativeUSDCBalance,
                data.borrowedAmount
            );
            // repay loan, where msg.sender = vault
            USDC_BRIDGED.safeTransferFrom(data.user, msg.sender, repayAmountFactoringInFeeAmount);
            // transfer remaining bridged USDC back to the user
            uint256 remainingBridgedUSDCBalance = USDC_BRIDGED.balanceOf(address(this));
            USDC_BRIDGED.safeTransferFrom(address(this), data.user, remainingBridgedUSDCBalance);
        } else {
            // call borrowBehalf to borrow tokens on behalf of user
            lTokenMapping[data.tokenToLoop].borrowBehalf(repayAmountFactoringInFeeAmount, data.user);
            // repay loan, where msg.sender = vault
            data.tokenToLoop.safeTransferFrom(data.user, msg.sender, repayAmountFactoringInFeeAmount);
        }
    }

    function getGLPPrice() internal view returns (uint256) {
        uint256 price = PLVGLP_ORACLE.getGLPPrice();
        require(price > 0, "invalid glp price returned");
        return price; //glp oracle returns price scaled to 18 decimals, no need to extend here
    }

    function getNotionalLoanAmountIn1e18(
        IERC20 _token,
        uint256 _amount,
        uint16 _leverage
    ) private view returns (uint256, IERC20) {
        // declare consts
        IERC20 _tokenToBorrow;
        uint256 _loanAmount;

        if (_token == PLVGLP) {
            uint256 _tokenPriceInEth;
            uint256 _usdcPriceInEth;
            uint256 _computedAmount;

            // plvGLP borrows USDC to loop
            _tokenToBorrow = USDC_BRIDGED;
            _tokenPriceInEth = PRICE_ORACLE.getUnderlyingPrice(address(lTokenMapping[_token]));
            _usdcPriceInEth = (PRICE_ORACLE.getUnderlyingPrice(address(lUSDC)) / 1e12);
            _computedAmount = (_amount * (_tokenPriceInEth / _usdcPriceInEth));

            _loanAmount = _getNotionalLoanAmountIn1e18(_computedAmount, _leverage);
        } else if (_token == USDC_NATIVE) {
            _tokenToBorrow = USDC_BRIDGED;
            _loanAmount = _getNotionalLoanAmountIn1e18(
                _amount, // we can just send over the exact amount
                _leverage
            );
        } else {
            // the rest of the contracts just borrow whatever token is supplied
            _tokenToBorrow = _token;
            _loanAmount = _getNotionalLoanAmountIn1e18(
                _amount, // we can just send over the exact amount
                _leverage
            );
        }

        return (_loanAmount, _tokenToBorrow);
    }

    function _getNotionalLoanAmountIn1e18(
        uint256 _notionalTokenAmountIn1e18,
        uint16 _leverage
    ) private pure returns (uint256) {
        unchecked {
            return ((_leverage - DIVISOR) * _notionalTokenAmountIn1e18) / DIVISOR;
        }
    }
}
