// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import '../interfaces/IERC20.sol';

library TransferHelper {
    // 安全的 transfer 函数
    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // 调用 ERC20 的 transfer 函数
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
            
        // 检查调用是否成功
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TF');
    }

    // 安全的 transferFrom 函数
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // 调用 ERC20 的 transferFrom 函数
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
            
        // 检查调用是否成功
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TF');
    }
} 