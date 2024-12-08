// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import './interfaces/IUniswapV3Factory.sol';
import './UniswapV3Pool.sol';

contract UniswapV3Factory is IUniswapV3Factory {
    // 工厂合约的所有者地址
    address public override owner;

    // 费率对应的 tick 间隔
    mapping(uint24 => int24) public override feeAmountTickSpacing;
    // token0,token1,fee -> pool 地址的映射
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    // 构造函数
    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        // 初始化支持的费率和对应的 tick 间隔
        feeAmountTickSpacing[500] = 10;   // 0.05% 的费率
        emit FeeAmountEnabled(500, 10);
        
        feeAmountTickSpacing[3000] = 60;  // 0.3% 的费率
        emit FeeAmountEnabled(3000, 60);
        
        feeAmountTickSpacing[10000] = 200; // 1% 的费率
        emit FeeAmountEnabled(10000, 200);
    }

    // 创建新的交易对
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override returns (address pool) {
        require(tokenA != tokenB);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0));
        require(feeAmountTickSpacing[fee] != 0);
        require(getPool[token0][token1][fee] == address(0));

        // 部署新的池合约
        pool = address(
            new UniswapV3Pool{
                salt: keccak256(abi.encode(token0, token1, fee))
            }(address(this), token0, token1, fee, feeAmountTickSpacing[fee])
        );

        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool; // 反向也要记录

        emit PoolCreated(token0, token1, fee, feeAmountTickSpacing[fee], pool);
    }

    // 启用新的费率
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public override {
        require(msg.sender == owner);
        require(fee < 1000000); // 费率不能超过 100%
        require(tickSpacing > 0 && tickSpacing < 16384);
        require(feeAmountTickSpacing[fee] == 0);

        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }

    // 设置新的所有者
    function setOwner(address _owner) external override {
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }
} 