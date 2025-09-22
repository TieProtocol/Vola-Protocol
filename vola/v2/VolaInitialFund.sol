// SPDX-License-Identifier: MIT

pragma solidity =0.8.20;

import { AccessControl } from "@openzeppelin/contracts-v4/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts-v4/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts-v4/token/ERC20/utils/SafeERC20.sol";

import { IVolaMarketV2 } from "../../interfaces/f(x)/IVolaMarketV2.sol";
import { IVolaTreasuryV2 } from "../../interfaces/f(x)/IVolaTreasuryV2.sol";
import { IVolaUSD } from "../../interfaces/f(x)/IVolaUSD.sol";

contract VolaInitialFund is AccessControl {
  using SafeERC20 for IERC20;

  /**********
   * Events *
   **********/

  /// @notice Emitted when the status of `volaWithdrawalEnabled` is updated.
  event ToggleVolaWithdrawalStatus();

  /**********
   * Errors *
   **********/

  /// @dev Thrown when try to withdraw both volaUSD and xToken.
  error ErrorVolaWithdrawalNotEnabled();

  /// @dev Thrown when the amount of base token is not enough.
  error ErrorInsufficientBaseToken();

  /// @dev Thrown when deposit after initialization.
  error ErrorInitialized();

  /// @dev Thrown when withdraw before initialization.
  error ErrorNotInitialized();

  /*************
   * Constants *
   *************/

  /// @notice The role for minter.
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  /// @notice The address of market contract.
  address public immutable market;

  /// @notice The address of treasury contract.
  address public immutable treasury;

  /// @notice The address of base token.
  address public immutable baseToken;

  /// @notice The address of fToken token.
  address public immutable fToken;

  /// @notice The address of xToken token.
  address public immutable xToken;

  /// @notice The address of volaUSD token.
  address public immutable volaUSD;

  /*************
   * Variables *
   *************/

  /// @notice Mapping from user address to pool shares.
  mapping(address => uint256) public shares;

  /// @notice The total amount of pool shares.
  uint256 public totalShares;

  /// @notice The total amount of volaUSD/fToken minted.
  uint256 public totalFToken;

  /// @notice The total amount of xToken minted.
  uint256 public totalXToken;

  /// @notice Whether the pool is initialized.
  bool public initialized;

  /// @notice Whether withdraw both volaUSD and xToken is enabled.
  bool public volaWithdrawalEnabled;

  /***************
   * Constructor *
   ***************/

  constructor(address _market, address _volaUSD) {
    address _treasury = IVolaMarketV2(_market).treasury();

    market = _market;
    treasury = _treasury;
    baseToken = IVolaTreasuryV2(_treasury).baseToken();
    fToken = IVolaTreasuryV2(_treasury).fToken();
    xToken = IVolaTreasuryV2(_treasury).xToken();
    volaUSD = _volaUSD;

    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Deposit base token to this contract.
  /// @param amount The amount of token to deposit.
  /// @param receiver The address of pool share recipient.
  function deposit(uint256 amount, address receiver) external {
    if (initialized) revert ErrorInitialized();

    IERC20(baseToken).safeTransferFrom(_msgSender(), address(this), amount);
    shares[receiver] += amount;
    totalShares += amount;
  }

  /// @notice Withdraw base token from this contract.
  /// @param receiver The address of base token recipient.
  /// @param minBaseOut The minimum amount of base token should receive.
  /// @return baseOut The amount of base token received.
  function withdrawBaseToken(address receiver, uint256 minBaseOut) external returns (uint256 baseOut) {
    if (!initialized) revert ErrorNotInitialized();

    uint256 _share = shares[_msgSender()];
    shares[_msgSender()] = 0;
    uint256 _totalShares = totalShares;
    uint256 _fAmount = (_share * totalFToken) / _totalShares;
    uint256 _xAmount = (_share * totalXToken) / _totalShares;

    uint256 _fBaseOut;
    if (volaUSD != address(0)) {
      (_fBaseOut, ) = IVolaUSD(volaUSD).redeem(baseToken, _fAmount, receiver, 0);
    } else {
      (_fBaseOut, ) = IVolaMarketV2(market).redeemFToken(_fAmount, receiver, 0);
    }
    // No need to approve xToken to market
    uint256 _xBaseOut = IVolaMarketV2(market).redeemXToken(_xAmount, receiver, 0);

    baseOut = _xBaseOut + _fBaseOut;
    if (baseOut < minBaseOut) revert ErrorInsufficientBaseToken();
  }

  /// @notice Withdraw volaUSD/fToken and xToken from this contract.
  /// @param receiver The address of token recipient.
  function withdraw(address receiver) external {
    if (!initialized) revert ErrorNotInitialized();
    if (!volaWithdrawalEnabled) revert ErrorVolaWithdrawalNotEnabled();

    uint256 _share = shares[_msgSender()];
    shares[_msgSender()] = 0;
    uint256 _totalShares = totalShares;
    uint256 _fAmount = (_share * totalFToken) / _totalShares;
    uint256 _xAmount = (_share * totalXToken) / _totalShares;

    if (volaUSD != address(0)) {
      IERC20(volaUSD).safeTransfer(receiver, _fAmount);
    } else {
      IERC20(fToken).safeTransfer(receiver, _fAmount);
    }
    IERC20(xToken).safeTransfer(receiver, _xAmount);
  }

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Initialize treasury with base token in this contract.
  function mint() external onlyRole(MINTER_ROLE) {
    if (initialized) revert ErrorInitialized();

    uint256 _balance = IERC20(baseToken).balanceOf(address(this));
    IERC20(baseToken).safeTransfer(treasury, _balance);
    (uint256 _totalFToken, uint256 _totalXToken) = IVolaTreasuryV2(treasury).initializeProtocol(
      IVolaTreasuryV2(treasury).getUnderlyingValue(_balance)
    );

    if (volaUSD != address(0)) {
      IERC20(fToken).safeApprove(volaUSD, _totalFToken);
      IVolaUSD(volaUSD).wrap(baseToken, _totalFToken, address(this));
    }

    totalFToken = _totalFToken;
    totalXToken = _totalXToken;
    initialized = true;
  }

  /// @notice Change the status of `volaWithdrawalEnabled`.
  function toggleVolaWithdrawalStatus() external onlyRole(DEFAULT_ADMIN_ROLE) {
    volaWithdrawalEnabled = !volaWithdrawalEnabled;

    emit ToggleVolaWithdrawalStatus();
  }
}
