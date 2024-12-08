// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library Constants {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 0x1000000000000000000000000;
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;
    
    // Tick 范围
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = 887272;
    
    // sqrt(price) 范围
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    // 协议费用分母
    uint256 internal constant FEE_PROTOCOL_DENOMINATOR = 10;
} 