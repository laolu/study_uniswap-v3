// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Factory.sol';

import './UniswapV3PoolDeployer.sol';
import './NoDelegateCall.sol';

import './UniswapV3Pool.sol';

/// @title Uniswap V3 工厂合约
/// @notice 负责部署和管理所有 Uniswap V3 交易对
contract UniswapV3Factory is IUniswapV3Factory, IUniswapV3PoolDeployer, NoDelegateCall {
    /// @dev 合约所有者地址
    address public override owner;

    /// @inheritdoc IUniswapV3Factory
    mapping(uint24 => int24) public override feeAmountTickSpacing;
    /// @inheritdoc IUniswapV3Factory
    /// @dev 存储所有已创建的交易对
    /// @notice tokenA地址 => tokenB地址 => 手续费 => 池子地址
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    /// @dev 构造函数
    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        // 初始化支持的手续费等级
        // 500 = 0.05%
        feeAmountTickSpacing[500] = 10;
        emit FeeAmountEnabled(500, 10);
        feeAmountTickSpacing[3000] = 60;
        emit FeeAmountEnabled(3000, 60);
        feeAmountTickSpacing[10000] = 200;
        emit FeeAmountEnabled(10000, 200);
    }

    /// @inheritdoc IUniswapV3Factory
    /// @notice 创建新的交易对
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    /// @param fee 手续费率
    /// @return pool 新创建的交易对地址
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override noDelegateCall returns (address pool) {
        // 确保代币地址不相同
        require(tokenA != tokenB);
        // 按地址大小排序代币
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // 确保代币地址有效
        require(token0 != address(0));
        int24 tickSpacing = feeAmountTickSpacing[fee];
        // 确保手续费率有效
        require(tickSpacing != 0);
        require(getPool[token0][token1][fee] == address(0));
        // 部署新的交易对合约
        pool = deploy(address(this), token0, token1, fee, tickSpacing);
        // 记录交易对地址
        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0][fee] = pool;
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    /// @inheritdoc IUniswapV3Factory
    /// @notice 设置新的所有者
    function setOwner(address _owner) external override {
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @inheritdoc IUniswapV3Factory
    /// @notice 启用新的手续费等级
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external override {
        require(msg.sender == owner);
        require(fee < 1000000);// 最大 100%
        // tick spacing is capped at 16384 to prevent the situation where tickSpacing is so large that
        // TickBitmap#nextInitializedTickWithinOneWord overflows int24 container from a valid tick
        // 16384 ticks represents a >5x price change with ticks of 1 bips
        require(tickSpacing > 0 && tickSpacing < 16384);
        require(feeAmountTickSpacing[fee] == 0);

        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }
}
