## Vola Protocol

Vola Protocol is a modular on-chain system for creating fractional and leveraged exposure to a base asset, aggregating fractional exposure into a unified wrapped stable asset, and coordinating incentives and governance via ve-style voting and gauges.

At its core, Vola splits a deposit of a base token into two fungible claims:
- Fractional Token (fToken): stable-like exposure to the base asset
- Leveraged Token (xToken): residual leveraged exposure

The system includes:
- A Treasury that holds collateral and enforces risk rules
- A Market that mints/redeems fToken and xToken against the Treasury
- A wrapped stable aggregator token, VolaUSD, that can hold a basket of fTokens across markets and integrates with Rebalance Pools
- Rebalance Pools and a Registry to manage fToken flow and rewards
- A Reserve Pool to fund on-chain incentives/bonuses
- Oracles and math libraries for pricing and accounting
- A voting-escrowed governance suite with gauges and distributors

This README gives a high-level map for product managers and integrators, with pointers to key contracts and typical flows.


## Repository layout

- `vola/v2/`
  - `TreasuryV2.sol`: Collateral accounting, pricing, limits, stability mode
  - `MarketV2.sol`: User-facing mint/redeem logic for fToken/xToken, fees, limits
  - `FractionalTokenV2.sol`: ERC20 fToken, `nav()` under stress uses Treasury state
  - `LeveragedTokenV2.sol`: ERC20 xToken, transfer cooling-off and `nav()`
  - `HypeUSD.sol` (contract `VolaUSD`): Wrapped stable aggregator and router for fToken flows and Rebalance Pools
- `vola/rebalance-pool/`
  - `RebalancePoolRegistry.sol`: Registry of pools, aggregate supply view
  - Shareable/Boostable pool implementations and helpers
- `vola/reserve-pool/`
  - `ReservePoolV2.sol`: Bonus funding with per-token ratios, callable by markets
- `vola/rebalancer/`
  - Rebalancing helpers for flows involving bonus tokens and VolaUSD
- `vola/oracle/`
  - `HypeOracle.sol`: Example price oracle using precompiles, conforms to `IVolaPriceOracleV2`
- `vola/rate-provider/`
  - Rate provider adapters for external integrations (e.g., ERC4626, wstHYPE)
- `vola/math/`
  - Deterministic math utilities for pricing, fees, and stability calculations
- `vola/VolaVault.sol`
  - Simple vault coordinating two assets (e.g., vola and LP) with a fixed ratio
- `voting-escrow/`
  - `VotingEscrow.vy`: ve-style time-weighted voting power
  - `VotingEscrowBoost.sol`, `VotingEscrowProxy.sol`: Boosting and proxying
  - `FeeDistributor.vy`, `TokenMinter.vy`: Fee flow and token emissions
  - `gauges/`: Gauges for liquidity and fundraising
- `External.sol`
  - Imports of OZ proxy primitives for upgradeability patterns


## Core concepts

- Collateral ratio (CR): Treasury tracks base-token collateral and adjusts mint/redeem boundaries; a stability mode can limit operations when CR is stressed.
- fToken NAV: In normal state, fToken targets 1.0 NAV; under collateralization, fToken `nav()` reflects pro-rata base claim.
- xToken NAV: Residual claim; becomes 0 in under-collateralization.
- VolaUSD: A wrapper/aggregator that holds fTokens across multiple supported markets. It can mint by routing through a Market, wrap existing fTokens, and deposit into Rebalance Pools in a single transaction.
- Rebalance Pools: Shared pools for fTokens that can route yield/incentives; a Registry surfaces the set of active pools and supply.
- Reserve Pool: A treasury for incentive/bonus tokens with configurable per-token payout ratios, drawn by Markets during flows.
- Governance: ve-style locking and gauges direct emissions or incentives; fees can be distributed pro-rata via the Fee Distributor.


## Key contracts and roles

### TreasuryV2
- Purpose: Canonical state machine for a base market; owns the collateral and mints/burns fToken/xToken.
- Selected views:
  - `baseToken()`, `fToken()`, `xToken()`
  - `collateralRatio()`: uint256 1e18
  - `isUnderCollateral()`: bool
  - `totalBaseToken()`: uint256
  - `currentBaseTokenPrice()`: uint256 1e18 (via oracle)
  - `maxMintableFToken(uint256 newCR)`/`maxMintableXToken(uint256 newCR)`
  - `maxRedeemableFToken(uint256 newCR)`/`maxRedeemableXToken(uint256 newCR)`
- Selected roles (AccessControl):
  - `DEFAULT_ADMIN_ROLE`: parameter management
  - `Vola_MARKET_ROLE`: authorized market
  - `SETTLE_WHITELIST_ROLE`, `PROTOCOL_INITIALIZER_ROLE`: specialized flows

### MarketV2
- Purpose: User bridge for minting/redeeming fToken and xToken against the Treasury; fees and stability mode gating.
- Selected views:
  - `mintPaused()`, `redeemPaused()`
  - `stabilityRatio()`: enter stability mode threshold (1e18)
  - `fTokenMintFeeRatio()`, `xTokenMintFeeRatio()`, `fTokenRedeemFeeRatio()`, `xTokenRedeemFeeRatio()`
  - Quoters: `getMintFToken(uint256 baseIn)`, `getMintXToken(uint256 baseIn)` return preview amounts, caps, and fees
- Selected state:
  - Immutable: `treasury`, `baseToken`, `fToken`, `xToken`
  - Mutable: `platform`, `reservePool`, `registry`, `volaUSD`
- Role: `EMERGENCY_DAO_ROLE` for circuit breakers

### FractionalTokenV2 (fToken)
- ERC20 with `ERC20Permit`.
- `nav()`: if under collateralization, computes pro-rata claim to Treasury base; else 1e18.
- Mint/burn restricted to `TreasuryV2`.

### LeveragedTokenV2 (xToken)
- ERC20 with `ERC20Permit` and transfer cooling-off enforcement.
- `nav()`: zero in under-collateralization; else residual claim.
- Roles: `DEFAULT_ADMIN_ROLE` (params), `THIRD_PARTY_MINTER_ROLE` (CEX/aggregator flows).

### VolaUSD (file: `vola/v2/HypeUSD.sol`)
- ERC20 with AccessControl that aggregates fToken exposures across supported markets and integrates with Rebalance Pools.
- Market management:
  - `getMarkets()`: address[] base tokens
  - `getRebalancePools()`: address[] pools
  - `nav()`: basket NAV
  - `isUnderCollateral()`: true if any underlying market is under-collateralized
- Flows:
  - `wrap(baseToken, amount, receiver)`: wrap fToken into VolaUSD shares
  - `wrapFrom(pool, amount, receiver)`: withdraw fToken from pool and wrap
  - `mint(baseToken, amountIn, receiver, minOut)`: route base->fToken via Market->shares
  - `earn(pool, amount, receiver)`: burn shares and deposit fToken into pool
  - `mintAndEarn(pool, amountIn, receiver, minOut)`: one-step mint to pool
  - `redeem(...)`: unwrap flows back to fToken/base as supported
- Whitelist for allowance bypass: admin can `flipApproveWhiteList(spender)` for integrators.

### Rebalance Pools and Registry
- `RebalancePoolRegistry.sol` tracks authorized pools and aggregates `totalSupply()` across them.
- Pool implementations under `vola/rebalance-pool/` can be shareable, boostable, or attach to external gauges.
- Splitters and wrappers help route rewards and handle reward tokens.

### ReservePoolV2
- Holds incentive tokens/ETH for bonus payouts.
- Admin: `updateBonusRatio(token, ratio)` with 0–1e18 caps.
- Market-only:
  - `requestBonus(token, recipient, originalAmount)` returns and transfers computed bonus, emits `RequestBonus`.
  - `getRequestBonus(token, originalAmount)` is a view to quote the bonus.

### Oracles
- `HypeOracle.sol`: Example oracle that reads from chain precompiles and scales to 1e18; implements `IVolaPriceOracleV2` returning (isValid, twap, min, max).
- Treasuries consume oracle price to value base collateral.

### Governance suite (voting-escrow and gauges)
- `VotingEscrow.vy`: Lock governance token for ve power (max 4 years), linear decay.
- `FeeDistributor.vy`: Distribute fees over time to ve holders.
- `VotingEscrowBoost.sol` and `gauges/*`: Boosted voting and per-pool gauges for directing emissions/liquidity incentives.
- `SmartWalletWhitelist.sol`: Optional safety for smart contract depositors.


## Typical flows

1) Mint fToken or xToken against a base token
- User queries `MarketV2.getMintFToken(baseIn)` or `getMintXToken(baseIn)` to preview limits and output.
- User approves base token to Market and calls `mint` function exposed by Market (not shown here) to receive fToken/xToken minted by Treasury.
- Market may pull bonus incentives from `ReservePoolV2` depending on configuration.

2) Wrap into VolaUSD and earn
- If holding fToken: call `VolaUSD.wrap(baseToken, amount, receiver)` to receive VolaUSD shares.
- To supply fToken into a pool in one step: `VolaUSD.mintAndEarn(pool, amountInBase, receiver, minOut)`.
- To move shares into a pool: `VolaUSD.earn(pool, amountShares, receiver)` burns shares and deposits equivalent fToken into `pool`.

3) Unwrap or redeem
- `VolaUSD.redeem(baseToken, amountIn, receiver, minOut)` unwraps shares back to fToken and/or base (as supported by the underlying market configuration).

4) Governance and rewards
- Lock governance token in `VotingEscrow` to obtain ve power; vote for gauges.
- Claim protocol fees from `FeeDistributor` and rewards via relevant gauge contracts.


## Roles and permissions (non-exhaustive)
- Protocol administration uses OpenZeppelin AccessControl:
  - `DEFAULT_ADMIN_ROLE`: global admin on a given contract
  - `EMERGENCY_DAO_ROLE` (Market): pause-style controls
  - `Vola_MARKET_ROLE` (Treasury): authorized market caller
  - `SETTLE_WHITELIST_ROLE`, `PROTOCOL_INITIALIZER_ROLE` (Treasury): specialized ops
  - `MARKET_ROLE` (ReservePool): who can draw bonus funds (e.g., Markets)
  - `THIRD_PARTY_MINTER_ROLE` (xToken): allows minting without cooling-off restrictions on transfer


## Development and integration

- Languages
  - Solidity 0.8.20 (most of `vola/*`)
  - Solidity 0.7.6 (`vola/VolaVault.sol`, `External.sol`)
  - Vyper 0.3.x (`voting-escrow/*` core)

- Tooling
  - Contracts are standard OZ-upgradeable style. You can compile with Foundry (forge) or Hardhat/Vieme as long as you pin compilers to the versions above and set remappings for OpenZeppelin v4 packages used.
  - Oracles and external adapters may require chain-specific precompiles (see `HypeOracle.sol`).

- Testing
  - Recommended to simulate stress cases: stability mode entry/exit, under-collateralization, mint/redeem caps, fee deltas across ranges, and bonus pool exhaustion.


## Safety and risk notes
- Under-collateralization: If `TreasuryV2.isUnderCollateral()` becomes true, fToken `nav()` falls to pro-rata base claim and xToken `nav()` becomes 0; VolaUSD halts flows that require minting and will surface the state via `isUnderCollateral()`.
- Stability mode: `MarketV2.stabilityRatio()` gates mint/redeem operations; separate flags allow pausing fToken mint or xToken redeem during stress.
- Oracle assumptions: Ensure `IVolaPriceOracleV2` implementations are robust, with TWAPs and bounds.
- Admin trust: Administrator roles can update parameters and whitelists; production deployments should use timelocks and multi-sigs.


## License

This repository is released under the MIT License. See SPDX headers in files.


## Acknowledgements

- Vote-escrow design and parts of the implementation are adapted from Curve Finance’s `veCRV` architecture. 