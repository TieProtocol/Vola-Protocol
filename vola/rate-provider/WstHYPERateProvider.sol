// SPDX-License-Identifier: MIT

pragma solidity =0.8.20;

import {IVolaRateProvider} from "../../interfaces/f(x)/IVolaRateProvider.sol";

// solhint-disable contract-name-camelcase
contract WstHYPERateProvider is IVolaRateProvider {
    /// @dev The address of stHype contract.
    address public immutable stHYPE;

    constructor(address _wstHYPE) {
        (bool success, bytes memory data) = _wstHYPE.staticcall(
            abi.encodeWithSignature("sthype()")
        );
        require(success, "Call failed");
        stHYPE = abi.decode(data, (address));
    }

    /// @inheritdoc IVolaRateProvider
    function getRate() external view override returns (uint256) {
        (bool success, bytes memory data) = stHYPE.staticcall(
            abi.encodeWithSignature("balancePerShare()")
        );
        require(success, "Call failed");
        uint rate = abi.decode(data, (uint256));
        require(rate > 0, "Invalid rate provider");
        return rate;
    }
}
