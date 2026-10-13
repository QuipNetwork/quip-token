// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {CREATE3} from 'solady-0.1.26/utils/CREATE3.sol';

/**
 * @title Constants
 * @dev Salt math shared by every deploy and verify script, so they can never
 *      drift on it (which would move the deterministic address).
 *
 *      QuipToken deploys through the canonical CreateX factory via CREATE3, so
 *      its address is a function of (CreateX, DEPLOYER, salt) — independent of
 *      constructor args and of the creation code. That is what lets one address
 *      hold the token on every chain even though the home chain's constructor
 *      args differ (it mints the supply; remotes do not). The salt is
 *      CreateX-permissioned: only DEPLOYER can ever claim the address on any
 *      chain (no CREATE3 address-squatting).
 *
 *      Same scheme as quip-swap-solidity's Omnibus and quip-solidity's
 *      canonical deploys:
 *        rawSalt     = DEPLOYER ‖ 0x00 ‖ bytes11(keccak256(label))
 *        guardedSalt = keccak256(bytes32(DEPLOYER) ‖ rawSalt)
 *        address     = CREATE3(CreateX, guardedSalt)
 */
library Constants {
  /// @notice The canonical CreateX factory, pre-deployed at this address on
  ///         essentially every EVM chain.
  address internal constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

  /// @notice The ops EOA every QuipToken address is permissioned to. COMPILED
  ///         IN, deliberately not configurable: the CreateX salt is
  ///         permissioned to this EOA, so the EOA *is* part of the address.
  ///
  ///         A wrong signer does not revert inside CreateX. It composes a salt
  ///         permissioned to *itself* and deploys successfully at a DIFFERENT,
  ///         unadvertised address. Hardcoding turns that into a loud
  ///         pre-broadcast failure (see DeployQuipTokenBase).
  ///
  ///         Same operator as the other quip canonical deployments. Changing it
  ///         changes the token address on every chain not yet deployed to.
  address internal constant DEPLOYER = 0xc68B64770Da7914DEb0EF238b048a0Bf3B5f6A26;

  /// @notice Version entropy for the salt (last 11 bytes of the permissioned
  ///         salt), derived from a human-readable version label.
  /// @dev The label is the source of truth; the entropy is always re-derived.
  ///      Each (DEPLOYER, label) pair maps to a distinct, permanently-consumed
  ///      address. A NEW label is what moves the address.
  /// @param versionLabel e.g. 'QUIP:QuipToken:v1.0.0'
  function saltEntropy(string memory versionLabel) internal pure returns (bytes11) {
    return bytes11(keccak256(bytes(versionLabel)));
  }

  /// @notice The raw CreateX salt, permissioned to DEPLOYER: 20-byte EOA ‖ 0x00
  ///         (no cross-chain redeploy protection — the address must be
  ///         claimable on every chain) ‖ 11-byte version entropy.
  /// @dev The 0x00 flag byte keeps `block.chainid` out of CreateX's guard.
  ///      Setting it to 0x01 would silently make the address per-chain, which
  ///      breaks the OFT mesh's one-address-everywhere property.
  function tokenSalt(string memory versionLabel) internal pure returns (bytes32) {
    return bytes32(abi.encodePacked(DEPLOYER, hex'00', saltEntropy(versionLabel)));
  }

  /// @notice The salt CreateX actually feeds to CREATE3 for a sender-prefixed
  ///         salt with the 0x00 flag byte (MsgSender + no-crosschain branch).
  /// @dev Any OTHER sender passing this same salt fails the prefix match and
  ///      falls to the permissionless branch, `keccak256(abi.encode(salt))`,
  ///      which derives an unrelated address. That is the anti-squat property.
  function guardedSalt(string memory versionLabel) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(bytes32(uint256(uint160(DEPLOYER))), tokenSalt(versionLabel)));
  }

  /// @notice The QuipToken address for a version label — pure offline math, no
  ///         RPC. CreateX's CREATE3 proxy is the standard one solady uses, so
  ///         solady's predictor applies with CreateX as the deployer.
  function predictToken(string memory versionLabel) internal pure returns (address) {
    return CREATE3.predictDeterministicAddress(guardedSalt(versionLabel), CREATEX);
  }
}
