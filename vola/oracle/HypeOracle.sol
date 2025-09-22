// SPDX-License-Identifier: MIT

pragma solidity =0.8.20;

import "../../interfaces/f(x)/IVolaPriceOracleV2.sol";

import {Math} from "@openzeppelin/contracts-v4/utils/math/Math.sol";


contract HypeOracle is IVolaPriceOracleV2 {

    struct TokenInfo {
        string name;
        uint64[] spots;
        uint64 deployerTradingFeeShare;
        address deployer;
        address evmContract;
        uint8 szDecimals;
        uint8 weiDecimals;
        int8 evmExtraWeiDecimals;
    }


    address constant ORACLE_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000807;
    address constant TOKEN_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080C;
    uint32 constant TOKEN_DECIMALS = 4;

    uint32 public immutable tokenIndex;

    /***************
     * Constructor *
     ***************/

    constructor(uint32 _tokenIndex)  {
        tokenIndex = _tokenIndex;
    }

    function getPrice()
    external
    view
    returns (
        bool isValid,
        uint256 twap,
        uint256 minPrice,
        uint256 maxPrice
    ){
        isValid = true;
        twap = oraclePx(tokenIndex);

        uint256 _scale = 10 ** (18 - TOKEN_DECIMALS);

        twap *= _scale;
        minPrice = twap * 9990 / 10000;
        maxPrice = twap * 10010 / 10000;
    }

    function oraclePx(uint32 index) public view returns (uint64) {
        bool success;
        bytes memory result;
        (success, result) = ORACLE_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));
        require(success, "OraclePx precompile call failed");
        return abi.decode(result, (uint64));
    }

    function tokenInfo(uint32 token) public view returns (TokenInfo memory) {
        bool success;
        bytes memory result;
        (success, result) = TOKEN_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(token));
        require(success, "TokenInfo precompile call failed");
        return abi.decode(result, (TokenInfo));
    }


}
