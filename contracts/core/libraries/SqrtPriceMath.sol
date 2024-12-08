// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import './FullMath.sol';
import './Constants.sol';

library SqrtPriceMath {
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        uint256 numerator1 = uint256(liquidity) << Constants.RESOLUTION;
        uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;

        require(sqrtRatioAX96 > 0);

        return
            roundUp
                ? FullMath.divRoundingUp(
                    FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96),
                    sqrtRatioAX96
                )
                : FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
    }

    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return
            roundUp
                ? FullMath.mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, Constants.Q96)
                : FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, Constants.Q96);
    }

    function getNextSqrtPriceFromInput(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint256 amountIn,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtPriceNextX96) {
        require(sqrtPriceX96 > 0);
        require(liquidity > 0);

        return
            zeroForOne
                ? getNextSqrtPriceFromAmount0RoundingUp(sqrtPriceX96, liquidity, amountIn, true)
                : getNextSqrtPriceFromAmount1RoundingDown(sqrtPriceX96, liquidity, amountIn, true);
    }

    function getNextSqrtPriceFromOutput(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint256 amountOut,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtPriceNextX96) {
        require(sqrtPriceX96 > 0);
        require(liquidity > 0);

        return
            zeroForOne
                ? getNextSqrtPriceFromAmount1RoundingDown(sqrtPriceX96, liquidity, amountOut, false)
                : getNextSqrtPriceFromAmount0RoundingUp(sqrtPriceX96, liquidity, amountOut, false);
    }

    function getNextSqrtPriceFromAmount0RoundingUp(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        if (amount == 0) return sqrtPriceX96;

        uint256 numerator1 = uint256(liquidity) << Constants.RESOLUTION;

        if (add) {
            uint256 product;
            if ((product = amount * sqrtPriceX96) / amount == sqrtPriceX96) {
                uint256 denominator = numerator1 + product;
                if (denominator >= numerator1)
                    return uint160(FullMath.mulDivRoundingUp(numerator1, sqrtPriceX96, denominator));
            }

            return uint160(FullMath.divRoundingUp(numerator1, (numerator1 / sqrtPriceX96) + amount));
        } else {
            uint256 product;
            require((product = amount * sqrtPriceX96) / amount == sqrtPriceX96 && numerator1 > product);
            uint256 denominator = numerator1 - product;
            return uint160(FullMath.mulDivRoundingUp(numerator1, sqrtPriceX96, denominator));
        }
    }

    function getNextSqrtPriceFromAmount1RoundingDown(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        if (add) {
            uint256 quotient = (amount <= type(uint160).max)
                ? (amount << Constants.RESOLUTION) / liquidity
                : FullMath.mulDiv(amount, Constants.Q96, liquidity);

            return uint160(uint256(sqrtPriceX96) + quotient);
        } else {
            uint256 quotient = (amount <= type(uint160).max)
                ? FullMath.divRoundingUp(amount << Constants.RESOLUTION, liquidity)
                : FullMath.mulDivRoundingUp(amount, Constants.Q96, liquidity);

            require(sqrtPriceX96 > quotient);
            return uint160(sqrtPriceX96 - quotient);
        }
    }

    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            amount0 = getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, true);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            amount0 = getAmount0Delta(sqrtRatioX96, sqrtRatioBX96, liquidity, true);
            amount1 = getAmount1Delta(sqrtRatioAX96, sqrtRatioX96, liquidity, true);
        } else {
            amount1 = getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, true);
        }
    }
} 