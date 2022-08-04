# FeeSplitter

## Setup

1. Set [system address](https://github.com/Degenswap/FeeSplitter/blob/163b601c2d5c8fc1688ade6bf7ba3e606ac96084/FeeSplitter.sol#L141) that should call this contract.
2. Set [router address](https://github.com/Degenswap/FeeSplitter/blob/163b601c2d5c8fc1688ade6bf7ba3e606ac96084/FeeSplitter.sol#L146) where to swap fee to project token.
3. Set [project](https://github.com/Degenswap/FeeSplitter/blob/163b601c2d5c8fc1688ade6bf7ba3e606ac96084/FeeSplitter.sol#L160-L165)
```Solidity
    function setCompanyWallet(
        address project, // project contract address where should be called claimFee()
        address token, // project token, that should be bought using fee
        address company, // company wallet address that should receive part of fee
        uint256 percentage // part of fee that should be send to company wallet (i.e. 20 = 20%)
    ) external onlyOwner 
```

## Usage

1. Call from backend function [getEstimateAmountOut()](https://github.com/Degenswap/FeeSplitter/blob/163b601c2d5c8fc1688ade6bf7ba3e606ac96084/FeeSplitter.sol#L174-L176).
2. Calculate `amountOutMin = amountOut * 99 / 100` for 1% slippage tolerance.
3. Call function [claimFeeFrom()](https://github.com/Degenswap/FeeSplitter/blob/163b601c2d5c8fc1688ade6bf7ba3e606ac96084/FeeSplitter.sol#L192-L198)

## Adjustment

When you call function [claimFeeFrom()](https://github.com/Degenswap/FeeSplitter/blob/163b601c2d5c8fc1688ade6bf7ba3e606ac96084/FeeSplitter.sol#L192-L198), check how much gas it use. Set this value as [claim gas cost](https://github.com/Degenswap/FeeSplitter/blob/163b601c2d5c8fc1688ade6bf7ba3e606ac96084/FeeSplitter.sol#L152-L154)
