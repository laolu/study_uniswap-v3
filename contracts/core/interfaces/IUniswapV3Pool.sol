// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import './IUniswapV3PoolEvents.sol';
import './IUniswapV3PoolActions.sol';
import './IUniswapV3PoolDerivedState.sol';
import './IUniswapV3PoolState.sol';

interface IUniswapV3Pool is
    IUniswapV3PoolEvents,
    IUniswapV3PoolActions,
    IUniswapV3PoolDerivedState,
    IUniswapV3PoolState
{} 