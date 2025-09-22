// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IVolaTokenWrapper } from "../interfaces/f(x)/IVolaTokenWrapper.sol";

contract VolaVault is ERC20Upgradeable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using SafeMathUpgradeable for uint256;

  /**********
   * Events *
   **********/

  /// @notice Emitted when the address of wrapper is updated.
  /// @param oldWrapper The address of the old token wrapper.
  /// @param newWrapper The address of the new token wrapper.
  event UpdateWrapper(address indexed oldWrapper, address indexed newWrapper);

  /// @notice Emitted when the vola ratio is updated due to rebalance.
  /// @param oldVolaRatio The old vola ratio, multipled by 1e18.
  /// @param newVolaRatio The new vola ratio, multipled by 1e18.
  event UpdateVolaRatio(uint256 oldVolaRatio, uint256 newVolaRatio);

  /// @notice Emitted when someone deposit tokens into this contract.
  /// @param owner The address who sends underlying asset.
  /// @param receiver The address who will receive the pool shares.
  /// @param volaAmount The amount of vola token deposited.
  /// @param lpAmount The amount of LP token deposited.
  /// @param shares The amount of vault share minted.
  event Deposit(address indexed owner, address indexed receiver, uint256 volaAmount, uint256 lpAmount, uint256 shares);

  /// @notice Emitted when someone withdraw asset from this contract.
  /// @param sender The address who call the function.
  /// @param receiver The address who will receive the assets.
  /// @param owner The address who owns the assets.
  /// @param shares The amounf of pool shares to withdraw.
  /// @param volaAmount The amount of vola token withdrawn.
  /// @param lpAmount The amount of LP token withdrawn.
  event Withdraw(
    address indexed sender,
    address indexed receiver,
    address indexed owner,
    uint256 volaAmount,
    uint256 lpAmount,
    uint256 shares
  );

  /// @notice Emitted when pool rebalance happens.
  /// @param volaBalance The total amount of vola token after rebalance.
  /// @param lpBalance The total amount of LP token after rebalance.
  event Rebalance(uint256 volaBalance, uint256 lpBalance);

  /*************
   * Constants *
   *************/

  uint256 private constant PRECISION = 1e18;

  /*************
   * Variables *
   *************/

  /// @notice The address of vola token.
  address public volaToken;

  /// @notice The address of LP token.
  address public lpToken;

  /// @notice The address of vola token and LP token wrapper contract.
  address public wrapper;

  /// @notice The ratio of vola token, multiplied by 1e18.
  /// @dev volaRatio:1-volaRatio = totalVolaToken:totalLpToken.
  uint256 public volaRatio;

  /// @notice The total amount of vola token managed in this contract.
  uint256 public totalVolaToken;

  /// @notice The total amount of LP token managed in this contract.
  uint256 public totalLpToken;

  /// @dev reserved slots for future usage.
  uint256[44] private __gap;

  /***************
   * Constructor *
   ***************/

  function initialize(
    address _volaToken,
    address _lpToken,
    address _wrapper,
    uint256 _volaRatio
  ) external initializer {
    require(_volaRatio <= PRECISION, "volaRatio out of bound");

    __Context_init();
    __ERC20_init("f(x) Balancer vola/ETH&vola", "VolaVault");
    __Ownable_init();

    volaToken = _volaToken;
    lpToken = _lpToken;

    _updateWrapper(_wrapper);

    volaRatio = _volaRatio;
    emit UpdateVolaRatio(0, _volaRatio);
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Deposit assets into this contract.
  /// @dev Make sure that the `volaToken` and `lpToken` are not fee on transfer token.
  /// @param _volaAmount The amount of vola token to deposit. Use `uint256(-1)` if user want to deposit all vola token.
  /// @param _lpAmount The amount of LP token to deposit. Use `uint256(-1)` if user want to deposit all LP token.
  /// @param _receiver The address of account who will receive the pool share.
  /// @return _shares The amount of pool shares received.
  function deposit(
    uint256 _volaAmount,
    uint256 _lpAmount,
    address _receiver
  ) external returns (uint256 _shares) {
    if (_volaAmount == uint256(-1)) {
      _volaAmount = IERC20Upgradeable(volaToken).balanceOf(msg.sender);
    }
    if (_lpAmount == uint256(-1)) {
      _lpAmount = IERC20Upgradeable(lpToken).balanceOf(msg.sender);
    }
    require(_volaAmount > 0 || _lpAmount > 0, "deposit zero amount");

    uint256 _totalSupply = totalSupply();
    uint256 _volaBalance = totalVolaToken;
    uint256 _lpBalance = totalLpToken;

    if (_totalSupply == 0) {
      // use volaRatio to compute shares, volaRatio : 1 - volaRatio = volaAmount : lpAmount
      uint256 _volaRatio = volaRatio;
      if (_volaRatio == 0) {
        _shares = _lpAmount;
        _volaAmount = 0;
      } else if (_volaRatio == PRECISION) {
        _shares = _volaAmount;
        _lpAmount = 0;
      } else {
        if (_volaAmount.mul(PRECISION - _volaRatio) <= _lpAmount.mul(_volaRatio)) {
          _lpAmount = _volaAmount.mul(PRECISION - _volaRatio).div(_volaRatio);
        } else {
          _volaAmount = _lpAmount.mul(_volaRatio).div(PRECISION - _volaRatio);
        }
        // use vola amount as initial share
        _shares = _volaAmount;
      }
    } else {
      // use existed balances to compute shares
      if (_volaBalance == 0) {
        _shares = _lpAmount.mul(_totalSupply).div(_lpBalance);
        _volaAmount = 0;
      } else if (_lpBalance == 0) {
        _shares = _volaAmount.mul(_totalSupply).div(_volaBalance);
        _lpAmount = 0;
      } else {
        uint256 _volaShares = _volaAmount.mul(_totalSupply).div(_volaBalance);
        uint256 _lpShares = _lpAmount.mul(_totalSupply).div(_lpBalance);
        if (_volaShares < _lpShares) {
          _shares = _volaShares;
          _lpAmount = _shares.mul(_lpBalance).div(_totalSupply);
        } else {
          _shares = _lpShares;
          _volaAmount = _shares.mul(_volaBalance).div(_totalSupply);
        }
      }
    }
    require(_shares > 0, "mint zero share");

    if (_volaAmount > 0) {
      totalVolaToken = _volaBalance.add(_volaAmount);
    }
    if (_lpAmount > 0) {
      totalLpToken = _lpBalance.add(_lpAmount);
    }
    _mint(_receiver, _shares);

    emit Deposit(msg.sender, _receiver, _volaAmount, _lpAmount, _shares);

    _depositVolaToken(msg.sender, _volaAmount);
    _depositLpToken(msg.sender, _lpAmount);
  }

  /// @notice Redeem assets from this contract.
  /// @param _shares The amount of pool shares to burn.  Use `uint256(-1)` if user want to redeem all pool shares.
  /// @param _receiver The address of account who will receive the assets.
  /// @param _owner The address of user to withdraw from.
  /// @return _volaAmount The amount of vola token withdrawn.
  /// @return _lpAmount The amount of LP token withdrawn.
  function redeem(
    uint256 _shares,
    address _receiver,
    address _owner
  ) external returns (uint256 _volaAmount, uint256 _lpAmount) {
    if (_shares == uint256(-1)) {
      _shares = balanceOf(_owner);
    }
    require(_shares > 0, "redeem zero share");

    if (msg.sender != _owner) {
      uint256 _allowance = allowance(_owner, msg.sender);
      require(_allowance >= _shares, "redeem exceeds allowance");
      if (_allowance != uint256(-1)) {
        // decrease allowance if it is not max
        _approve(_owner, msg.sender, _allowance - _shares);
      }
    }

    uint256 _totalSupply = totalSupply();
    uint256 _volaBalance = totalVolaToken;
    uint256 _lpBalance = totalLpToken;

    _burn(msg.sender, _shares);

    _volaAmount = _volaBalance.mul(_shares).div(_totalSupply);
    _lpAmount = _lpBalance.mul(_shares).div(_totalSupply);

    if (_volaAmount > 0) {
      totalVolaToken = _volaBalance.sub(_volaAmount);
    }
    if (_lpAmount > 0) {
      totalLpToken = _lpBalance.sub(_lpAmount);
    }

    emit Withdraw(msg.sender, _receiver, _owner, _volaAmount, _lpAmount, _shares);

    _withdrawVolaToken(_volaAmount, _receiver);
    _withdrawLpToken(_lpAmount, _receiver);
  }

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Rebalance the vola token and LP token to target ratio.
  /// @param _targetVolaRatio The expected target vola token ratio.
  /// @param _amount The amount of vola token to wrap or LP token to unwrap.
  /// @param _minOut The minimum amount of wrapped/unwrapped token.
  /// @return _amountOut The actual amount of wrapped/unwrapped token.
  function rebalance(
    uint256 _targetVolaRatio,
    uint256 _amount,
    uint256 _minOut
  ) external onlyOwner returns (uint256 _amountOut) {
    require(_targetVolaRatio <= PRECISION, "volaRatio out of bound");

    address _wrapper = wrapper;
    uint256 _oldVolaRatio = volaRatio;
    uint256 _volaBalance = totalVolaToken;
    uint256 _lpBalance = totalLpToken;

    if (_oldVolaRatio < _targetVolaRatio) {
      // we need to unwrap some LP token
      require(_amount <= _lpBalance, "insufficient LP token");
      _withdrawLpToken(_amount, _wrapper);
      _amountOut = IVolaTokenWrapper(_wrapper).unwrap(_amount);
      _depositVolaToken(address(this), _amountOut);

      _volaBalance = _volaBalance.add(_amountOut);
      _lpBalance = _lpBalance - _amount;
    } else {
      // we need to wrap some vola token
      require(_amount <= _volaBalance, "insufficient vola token");
      _withdrawVolaToken(_amount, _wrapper);
      _amountOut = IVolaTokenWrapper(_wrapper).wrap(_amount);
      _depositLpToken(address(this), _amountOut);

      _volaBalance = _volaBalance - _amount;
      _lpBalance = _lpBalance.add(_amountOut);
    }
    require(_amountOut >= _minOut, "insufficient output");

    totalVolaToken = _volaBalance;
    totalLpToken = _lpBalance;

    _targetVolaRatio = _volaBalance.mul(PRECISION).div(_volaBalance.add(_lpBalance));
    volaRatio = _targetVolaRatio;

    emit Rebalance(_volaBalance, _lpBalance);

    emit UpdateVolaRatio(_oldVolaRatio, _targetVolaRatio);
  }

  /// @notice Update the address of token wrapper contract.
  /// @param _newWrapper The address of new token wrapper contract.
  function updateWrapper(address _newWrapper) external onlyOwner {
    _updateWrapper(_newWrapper);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to update the wrapper contract.
  /// @param _newWrapper The address of new token wrapper contract.
  function _updateWrapper(address _newWrapper) internal {
    require(volaToken == IVolaTokenWrapper(_newWrapper).src(), "src mismatch");
    require(lpToken == IVolaTokenWrapper(_newWrapper).dst(), "dst mismatch");

    address _oldWrapper = wrapper;
    wrapper = _newWrapper;

    emit UpdateWrapper(_oldWrapper, _newWrapper);
  }

  /// @dev Internal function to deposit vola token to this contract.
  /// @param _sender The address of token sender.
  /// @param _amount The amount of vola token to deposit.
  function _depositVolaToken(address _sender, uint256 _amount) internal virtual {
    if (_sender != address(this)) {
      IERC20Upgradeable(volaToken).safeTransferFrom(_sender, address(this), _amount);
    }
  }

  /// @dev Internal function to deposit LP token to this contract.
  /// @param _sender The address of token sender.
  /// @param _amount The amount of LP token to deposit.
  function _depositLpToken(address _sender, uint256 _amount) internal virtual {
    if (_sender != address(this)) {
      IERC20Upgradeable(lpToken).safeTransferFrom(_sender, address(this), _amount);
    }
  }

  /// @dev Internal function to withdraw vola token.
  /// @param _amount The amount of vola token to withdraw.
  /// @param _receiver The address of recipient of the vola token.
  function _withdrawVolaToken(uint256 _amount, address _receiver) internal virtual {
    IERC20Upgradeable(volaToken).safeTransfer(_receiver, _amount);
  }

  /// @dev Internal function to withdraw LP token.
  /// @param _amount The amount of LP token to withdraw.
  /// @param _receiver The address of recipient of the LP token.
  function _withdrawLpToken(uint256 _amount, address _receiver) internal virtual {
    IERC20Upgradeable(lpToken).safeTransfer(_receiver, _amount);
  }
}
