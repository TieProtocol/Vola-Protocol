// SPDX-License-Identifier: MIT

pragma solidity =0.8.20;

import { IVolaBoostableRebalancePool } from "../../interfaces/f(x)/IVolaBoostableRebalancePool.sol";

import { ShareableRebalancePoolV2 } from "./ShareableRebalancePoolV2.sol";

contract VolaUSDShareableRebalancePool is ShareableRebalancePoolV2 {
  /***************
   * Constructor *
   ***************/

  constructor(
    address _volan,
    address _ve,
    address _veHelper,
    address _minter
  ) ShareableRebalancePoolV2(_volan, _ve, _veHelper, _minter) {}

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @inheritdoc IVolaBoostableRebalancePool
  function withdraw(uint256 _amount, address _receiver) external override {
    // not allowed to withdraw as fToken in volaUSD.
    // _withdraw(_msgSender(), _amount, _receiver);
  }
}
