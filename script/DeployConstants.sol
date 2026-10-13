// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

/**
 * @title DeployConstants
 * @dev Every value that decides WHAT gets deployed WHERE, compiled in.
 *
 *      WHY COMPILED IN RATHER THAN ENV. A wrong label does not revert: it derives
 *      a different salt and deploys successfully at an unadvertised address. A
 *      wrong initial holder is worse: on a remote chain it mints a SECOND full
 *      supply. A constant here cannot be stale at runtime — changing it is a
 *      source edit that shows up in the diff and in review.
 *
 *      ONE ADDRESS EVERYWHERE. Every chain, mainnet and testnet, deploys under
 *      the single LABEL, so QuipToken has one address on all of them. The
 *      families still differ in endpoint, home chain and supply holder.
 *
 *      HOME CHAIN. Exactly one chain per family receives `TOTAL_SUPPLY` at
 *      construction. Every other chain starts at zero and only ever holds what
 *      was bridged in.
 */
library DeployConstants {
  // ── Token metadata ──────────────────────────────────────────────────

  /// @notice ERC20 name. Permanent: it is part of the deployed state and of
  ///         every explorer and exchange listing.
  string internal constant NAME = 'Quip';

  /// @notice ERC20 symbol. Permanent, as NAME.
  string internal constant SYMBOL = 'QUIP';

  // ── Salt label ──────────────────────────────────────────────────────

  /// @notice Salt version label for EVERY deployment, mainnet and testnet.
  /// @dev One label means one QuipToken address on every chain, in both
  ///      families — testnet and mainnet tokens live at the same address.
  ///
  ///      The cost: a CREATE3 address can be claimed once per chain, so a
  ///      testnet that needs a redeploy can only get one by bumping this label,
  ///      which moves the address everywhere. That is free until the first
  ///      mainnet deploy and impossible after it (bumping would orphan live
  ///      balances). Freeze it before mainnet; never bump it afterwards.
  string internal constant LABEL = 'QUIP:QuipToken:v1.0.0';

  // ── LayerZero ───────────────────────────────────────────────────────

  /// @notice LayerZero EndpointV2, same address on every LayerZero mainnet.
  address internal constant MAINNET_LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

  /// @notice LayerZero EndpointV2, same address on every LayerZero testnet.
  address internal constant TESTNET_LZ_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;

  // ── Home chain and supply recipient ─────────────────────────────────

  /// @notice The one mainnet that mints `TOTAL_SUPPLY`.
  uint256 internal constant MAINNET_HOME_CHAIN = 1; // Ethereum

  /// @notice The one testnet that mints `TOTAL_SUPPLY`.
  uint256 internal constant TESTNET_HOME_CHAIN = 11_155_111; // Sepolia

  /// @notice Receives the entire mainnet supply at construction.
  /// @dev UNSET ON PURPOSE. A mainnet home-chain deploy aborts while this is
  ///      zero (see DeployQuipTokenBase), so the token cannot ship with its
  ///      supply minted to nobody — or to a placeholder. Set it to the treasury
  ///      multisig in a reviewed commit before the mainnet deploy.
  address internal constant MAINNET_INITIAL_HOLDER = address(0);

  /// @notice Receives the entire testnet supply: the ops EOA, so testnet
  ///         tokens can be distributed without a multisig round-trip.
  address internal constant TESTNET_INITIAL_HOLDER = 0xc68B64770Da7914DEb0EF238b048a0Bf3B5f6A26;

  // ── Chain sets ──────────────────────────────────────────────────────

  /// @notice Chains the MAINNET label deploys to. Doubles as the deploy
  ///         script's allowlist.
  function mainnetChains() internal pure returns (uint256[] memory chains) {
    chains = new uint256[](2);
    chains[0] = 1; // Ethereum (home)
    chains[1] = 8453; // Base
  }

  /// @notice Chains the TESTNET label deploys to.
  function testnetChains() internal pure returns (uint256[] memory chains) {
    chains = new uint256[](2);
    chains[0] = 11_155_111; // Sepolia (home)
    chains[1] = 84_532; // Base Sepolia
  }

  /// @notice Whether `chainId` is a mainnet target.
  function isMainnet(uint256 chainId) internal pure returns (bool) {
    return _contains(mainnetChains(), chainId);
  }

  /// @notice Whether `chainId` is a testnet target.
  function isTestnet(uint256 chainId) internal pure returns (bool) {
    return _contains(testnetChains(), chainId);
  }

  /// @notice The LayerZero EndpointV2 for a given chain.
  function lzEndpointFor(uint256 chainId) internal pure returns (address) {
    if (isMainnet(chainId)) return MAINNET_LZ_ENDPOINT;
    if (isTestnet(chainId)) return TESTNET_LZ_ENDPOINT;
    revert('DeployConstants: chain id is in neither the mainnet nor the testnet set');
  }

  /// @notice Whether `chainId` is its family's home chain.
  function isHomeChain(uint256 chainId) internal pure returns (bool) {
    return chainId == MAINNET_HOME_CHAIN || chainId == TESTNET_HOME_CHAIN;
  }

  /// @notice The constructor's `initialHolder_` for a given chain: the family's
  ///         supply recipient on its home chain, `address(0)` everywhere else.
  function initialHolderFor(uint256 chainId) internal pure returns (address) {
    if (chainId == MAINNET_HOME_CHAIN) return MAINNET_INITIAL_HOLDER;
    if (chainId == TESTNET_HOME_CHAIN) return TESTNET_INITIAL_HOLDER;
    if (isMainnet(chainId) || isTestnet(chainId)) return address(0);
    revert('DeployConstants: chain id is in neither the mainnet nor the testnet set');
  }

  function _contains(uint256[] memory haystack, uint256 needle) private pure returns (bool) {
    for (uint256 i; i < haystack.length; i++) {
      if (haystack[i] == needle) return true;
    }
    return false;
  }
}
