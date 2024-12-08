// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import './FullMath.sol';
import './FixedPoint128.sol';
import './LiquidityMath.sol';

library Position {
    struct Info {
        uint128 liquidity;           // 流动性数量
        uint256 feeGrowthInside0LastX128;  // token0 的累积费用增长
        uint256 feeGrowthInside1LastX128;  // token1 的累积费用增长
        uint128 tokensOwed0;         // 待领取的 token0 数量
        uint128 tokensOwed1;         // 待领取的 token1 数量
    }

    // 获取头寸信息
    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (Position.Info storage position) {
        position = self[keccak256(abi.encodePacked(owner, tickLower, tickUpper))];
    }

    // 更新头寸
    function update(
        Info storage self,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal {
        uint128 liquidityNext;
        
        // 计算新的流动性
        if (liquidityDelta == 0) {
            require(self.liquidity > 0, 'NP'); // 必须有流动性
            liquidityNext = self.liquidity;
        } else {
            liquidityNext = LiquidityMath.addDelta(self.liquidity, liquidityDelta);
        }

        // 计算待领取的手续费
        uint128 tokensOwed0 = uint128(
            FullMath.mulDiv(
                feeGrowthInside0X128 - self.feeGrowthInside0LastX128,
                self.liquidity,
                FixedPoint128.Q128
            )
        );
        uint128 tokensOwed1 = uint128(
            FullMath.mulDiv(
                feeGrowthInside1X128 - self.feeGrowthInside1LastX128,
                self.liquidity,
                FixedPoint128.Q128
            )
        );

        // 更新状态
        if (liquidityDelta != 0) self.liquidity = liquidityNext;
        
        // 更新累积费用
        self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        self.feeGrowthInside1LastX128 = feeGrowthInside1X128;

        // 更新待领取的代币数量
        if (tokensOwed0 > 0 || tokensOwed1 > 0) {
            self.tokensOwed0 += tokensOwed0;
            self.tokensOwed1 += tokensOwed1;
        }
    }
} 