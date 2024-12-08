// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import './interfaces/IUniswapV3Pool.sol';
import './interfaces/IUniswapV3PoolEvents.sol';
import './interfaces/IUniswapV3PoolActions.sol';
import './interfaces/IUniswapV3PoolDerivedState.sol';
import './interfaces/IUniswapV3PoolState.sol';
import './interfaces/IERC20.sol';
import './interfaces/callback/IUniswapV3FlashCallback.sol';
import './interfaces/callback/IUniswapV3MintCallback.sol';
import './interfaces/callback/IUniswapV3SwapCallback.sol';

import './libraries/LiquidityMath.sol';
import './libraries/SqrtPriceMath.sol';
import './libraries/Tick.sol';
import './libraries/TickBitmap.sol';
import './libraries/TickMath.sol';
import './libraries/SwapMath.sol';
import './libraries/Constants.sol';
import './libraries/Position.sol';
import './libraries/TransferHelper.sol';
import './libraries/FixedPoint128.sol';

contract UniswapV3Pool is 
    IUniswapV3Pool,
    IUniswapV3PoolEvents,
    IUniswapV3PoolActions,
    IUniswapV3PoolDerivedState,
    IUniswapV3PoolState
{
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    // 全局状态变量
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;

    // 池状态
    struct Slot0 {
        uint160 sqrtPriceX96;
        int24 tick;
        uint8 feeProtocol;
        bool unlocked;
    }
    Slot0 public slot0;

    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;
    uint128 public liquidity;

    // 协议费用
    struct ProtocolFees {
        uint128 token0;
        uint128 token1;
    }
    ProtocolFees public protocolFees;

    // 映射状态变量
    mapping(int24 => Tick.Info) public ticks;
    mapping(int16 => uint256) public tickBitmap;
    mapping(bytes32 => Position.Info) public positions;

    // 构造函数
    constructor(
        address _factory,
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing
    ) {
        factory = _factory;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
    }

    // 修饰器
    modifier lock() {
        require(slot0.unlocked, 'LOK');
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

    // 初始化函数
    function initialize(uint160 sqrtPriceX96) external override {
        require(slot0.sqrtPriceX96 == 0, 'AI');

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            feeProtocol: 0,
            unlocked: true
        });

        emit Initialize(sqrtPriceX96, tick);
    }

    // 添加流动性
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        require(amount > 0);
        require(tickLower < tickUpper);
        require(tickLower >= TickMath.MIN_TICK);
        require(tickUpper <= TickMath.MAX_TICK);
        require(tickLower % tickSpacing == 0);
        require(tickUpper % tickSpacing == 0);

        // 更新流动性
        Position.Info storage position = positions.get(
            keccak256(abi.encodePacked(msg.sender, tickLower, tickUpper))
        );

        position.liquidity = LiquidityMath.addDelta(position.liquidity, int128(amount));

        // 更新 tick
        ticks.update(
            tickLower,
            slot0.tick,
            int128(amount),
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128,
            false
        );

        ticks.update(
            tickUpper,
            slot0.tick,
            int128(amount),
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128,
            true
        );

        // 更新 bitmap
        tickBitmap.flipTick(tickLower, tickSpacing);
        tickBitmap.flipTick(tickUpper, tickSpacing);

        // 计算需要的 token 数量
        (amount0, amount1) = SqrtPriceMath.getAmountsForLiquidity(
            slot0.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount
        );

        // 调用回调函数进行转账
        if (amount0 > 0 || amount1 > 0) {
            IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);
        }

        emit Mint(msg.sender, recipient, tickLower, tickUpper, amount, amount0, amount1);
    }

    // 移除流动性
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        require(amount > 0);
        
        Position.Info storage position = positions.get(
            keccak256(abi.encodePacked(msg.sender, tickLower, tickUpper))
        );

        require(position.liquidity >= amount);

        // 更新流动性
        position.liquidity = LiquidityMath.addDelta(position.liquidity, -int128(amount));

        // 更新 tick
        ticks.update(
            tickLower,
            slot0.tick,
            -int128(amount),
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128,
            false
        );

        ticks.update(
            tickUpper,
            slot0.tick,
            -int128(amount),
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128,
            true
        );

        // 更新 bitmap
        if (position.liquidity == 0) {
            tickBitmap.flipTick(tickLower, tickSpacing);
            tickBitmap.flipTick(tickUpper, tickSpacing);
        }

        // 计算返还的 token 数量
        (amount0, amount1) = SqrtPriceMath.getAmountsForLiquidity(
            slot0.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount
        );

        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
    }

    // 收集手续费
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override lock returns (uint128 amount0, uint128 amount1) {
        Position.Info storage position = positions.get(
            keccak256(abi.encodePacked(msg.sender, tickLower, tickUpper))
        );

        amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        emit Collect(msg.sender, recipient, tickLower, tickUpper, amount0, amount1);
    }

    // 交换
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external override lock returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, 'AS');
        require(
            zeroForOne
                ? sqrtPriceLimitX96 < slot0.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > slot0.sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
            'SPL'
        );

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0.sqrtPriceX96,
            tick: slot0.tick,
            feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
            liquidity: liquidity
        });

        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            StepComputations memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                tickSpacing,
                zeroForOne
            );

            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath
                .computeSwapStep(
                    state.sqrtPriceX96,
                    (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                        ? sqrtPriceLimitX96
                        : step.sqrtPriceNextX96,
                    state.liquidity,
                    state.amountSpecifiedRemaining,
                    fee
                );

            if (state.amountSpecifiedRemaining > 0) {
                state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                state.amountCalculated = state.amountCalculated.sub(step.amountOut.toInt256());
            } else {
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated = state.amountCalculated.add(
                    (step.amountIn + step.feeAmount).toInt256()
                );
            }

            if (state.liquidity > 0)
                state.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, Constants.Q128, state.liquidity);

            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    if (!zeroForOne) step.tickNext--;
                    int128 liquidityNet = ticks.cross(
                        step.tickNext,
                        (zeroForOne ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128),
                        (zeroForOne ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128)
                    );
                    if (zeroForOne) liquidityNet = -liquidityNet;

                    state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
                }

                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        if (state.tick != slot0.tick) {
            (slot0.sqrtPriceX96, slot0.tick) = (state.sqrtPriceX96, state.tick);
        }

        if (liquidity != state.liquidity) liquidity = state.liquidity;

        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            amount0 = amountSpecified - state.amountSpecifiedRemaining;
            amount1 = state.amountCalculated;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
            amount0 = state.amountCalculated;
            amount1 = amountSpecified - state.amountSpecifiedRemaining;
        }

        // 调用回调函数进行转账
        if (amount0 != 0 || amount1 != 0) {
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
        }

        emit Swap(msg.sender, recipient, amount0, amount1, slot0.sqrtPriceX96, state.liquidity, slot0.tick);
    }

    // 闪电贷
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override lock {
        uint128 _liquidity = liquidity;
        require(_liquidity > 0, 'L');

        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, fee, 1e6);
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, fee, 1e6);
        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        if (amount0 > 0) TransferHelper.safeTransfer(token0, recipient, amount0);
        if (amount1 > 0) TransferHelper.safeTransfer(token1, recipient, amount1);

        IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(fee0, fee1, data);

        uint256 balance0After = IERC20(token0).balanceOf(address(this));
        uint256 balance1After = IERC20(token1).balanceOf(address(this));

        require(balance0Before.add(fee0) <= balance0After, 'F0');
        require(balance1Before.add(fee1) <= balance1After, 'F1');

        uint256 paid0 = balance0After - balance0Before;
        uint256 paid1 = balance1After - balance1Before;

        if (paid0 > 0) {
            uint8 feeProtocol0 = slot0.feeProtocol >> 4;
            if (feeProtocol0 > 0) {
                uint256 fees0 = (paid0 * feeProtocol0) / Constants.FEE_PROTOCOL_DENOMINATOR;
                if (fees0 > 0) protocolFees.token0 += uint128(fees0);
            }
        }
        if (paid1 > 0) {
            uint8 feeProtocol1 = slot0.feeProtocol & 0xf;
            if (feeProtocol1 > 0) {
                uint256 fees1 = (paid1 * feeProtocol1) / Constants.FEE_PROTOCOL_DENOMINATOR;
                if (fees1 > 0) protocolFees.token1 += uint128(fees1);
            }
        }

        emit Flash(msg.sender, recipient, amount0, amount1, paid0, paid1);
    }

    // 设置协议费用
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override lock {
        require(msg.sender == IUniswapV3Factory(factory).owner());
        require(
            (feeProtocol0 == 0 || feeProtocol0 >= 4 && feeProtocol0 <= 10) &&
            (feeProtocol1 == 0 || feeProtocol1 >= 4 && feeProtocol1 <= 10)
        );
        uint8 feeProtocol0Old = slot0.feeProtocol >> 4;
        uint8 feeProtocol1Old = slot0.feeProtocol & 0xf;
        slot0.feeProtocol = (feeProtocol0 << 4) | feeProtocol1;
        emit SetFeeProtocol(feeProtocol0Old, feeProtocol1Old, feeProtocol0, feeProtocol1);
    }

    // 收集协议费用
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override lock returns (uint128 amount0, uint128 amount1) {
        require(msg.sender == IUniswapV3Factory(factory).owner());
        amount0 = amount0Requested > protocolFees.token0 ? protocolFees.token0 : amount0Requested;
        amount1 = amount1Requested > protocolFees.token1 ? protocolFees.token1 : amount1Requested;

        if (amount0 > 0) {
            if (amount0 == protocolFees.token0) amount0--;
            protocolFees.token0 -= amount0;
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            if (amount1 == protocolFees.token1) amount1--;
            protocolFees.token1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        emit CollectProtocol(msg.sender, recipient, amount0, amount1);
    }
}

// 辅助结构体
struct SwapState {
    int256 amountSpecifiedRemaining;
    int256 amountCalculated;
    uint160 sqrtPriceX96;
    int24 tick;
    uint256 feeGrowthGlobalX128;
    uint128 liquidity;
}

struct StepComputations {
    uint160 sqrtPriceStartX96;
    int24 tickNext;
    bool initialized;
    uint160 sqrtPriceNextX96;
    uint256 amountIn;
    uint256 amountOut;
    uint256 feeAmount;
}