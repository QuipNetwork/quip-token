// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {OFT} from '@layerzerolabs/oft-evm/contracts/OFT.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title QuipToken
 * @dev The Quip network token: a plain LayerZero V2 OFT, modelled one-for-one on
 *      the LayerZero ZRO token (`LayerZeroToken`,
 *      0x6985884C4392D348587B19cb9eAAf157F13271cd). No proxy, no mint function,
 *      no pause, no fees — ERC20 + OFT + Ownable, nothing else.
 *
 *      ONE DELIBERATE DIFFERENCE FROM ZRO. ZRO ships two sources at one address:
 *      the home-chain build mints the whole supply to a hardcoded treasury, and
 *      every remote-chain build has an empty constructor. QuipToken folds both
 *      into one contract: `initialHolder_` receives the entire `TOTAL_SUPPLY` on
 *      the home chain and is `address(0)` everywhere else. The deploy scripts
 *      derive it from compiled-in constants, never from the environment, so a
 *      remote chain cannot be handed a second supply by a mistyped env var.
 *
 *      SUPPLY. The constructor is the only place supply is created on the home
 *      chain. Afterwards, OFT `_credit` re-mints on a destination only what
 *      `_debit` burned on a source, so the sum of `totalSupply()` across chains
 *      plus in-flight transfers never exceeds `TOTAL_SUPPLY`.
 *
 *      OWNER. Controls LayerZero configuration only (peers, enforced options,
 *      delegate, msg inspector, pre-crime). It cannot mint, freeze, or move
 *      balances.
 */
contract QuipToken is OFT {
  /// @notice The full supply, minted once on the home chain at deployment.
  uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

  /// @param name_ ERC20 name
  /// @param symbol_ ERC20 symbol
  /// @param lzEndpoint_ the chain's LayerZero EndpointV2
  /// @param delegate_ owner, and LayerZero delegate for endpoint configuration
  /// @param initialHolder_ receives `TOTAL_SUPPLY` on the home chain;
  ///        `address(0)` on every remote chain, which mints nothing
  constructor(
    string memory name_,
    string memory symbol_,
    address lzEndpoint_,
    address delegate_,
    address initialHolder_
  ) OFT(name_, symbol_, lzEndpoint_, delegate_) Ownable(delegate_) {
    if (initialHolder_ != address(0)) _mint(initialHolder_, TOTAL_SUPPLY);
  }
}
