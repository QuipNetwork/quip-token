// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {DeployConstants} from './DeployConstants.sol';

/**
 * @title LzConfig
 * @dev Per-chain LayerZero pathway configuration for the QuipToken mesh,
 *      compiled in for the same reason DeployConstants is: a wrong DVN or
 *      library does not revert, it silently routes the token's messages through
 *      infrastructure nobody reviewed.
 *
 *      SOURCE. Every address below is from LayerZero's official deployment
 *      metadata (https://metadata.layerzero-api.com/v1/metadata, fetched
 *      2026-10-13): the chain's ULN302 send/receive libraries, its executor, and
 *      the non-lzRead DVN deployments of LayerZero Labs and Nethermind.
 *
 *      SECURITY STACK. Every pathway requires BOTH DVNs (2-of-2, no optional
 *      DVNs). A message is only delivered once two independent operators have
 *      verified it. Pinning the config explicitly also stops a later change to
 *      LayerZero's per-chain defaults from changing the token's security.
 *
 *      SYMMETRY. For a message A → B, the send config on A and the receive
 *      config on B must name the SAME operators, the same count, and the same
 *      block confirmations (A's). `confirmations` is therefore the SOURCE
 *      chain's finality depth, used on both ends of its outbound pathways.
 */
library LzConfig {
  struct Chain {
    uint256 chainId;
    uint32 eid;
    address sendLib; // SendUln302
    address receiveLib; // ReceiveUln302
    address executor;
    address dvnLayerZeroLabs;
    address dvnNethermind;
    uint64 confirmations; // block confirmations for messages SENT from this chain
  }

  /// @notice Max payload the executor will deliver. OFT messages are 40 bytes
  ///         plus any compose payload.
  uint32 internal constant MAX_MESSAGE_SIZE = 10_000;

  /// @notice Gas forwarded to `lzReceive` on the destination, enforced on every
  ///         send so a caller cannot under-fund delivery and strand tokens.
  ///         A plain OFT credit (one `_mint`) uses well under half of this.
  uint128 internal constant LZ_RECEIVE_GAS = 80_000;

  function chain(uint256 chainId) internal pure returns (Chain memory) {
    if (chainId == 1) {
      return Chain({
        chainId: 1,
        eid: 30_101,
        sendLib: 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1,
        receiveLib: 0xc02Ab410f0734EFa3F14628780e6e695156024C2,
        executor: 0x173272739Bd7Aa6e4e214714048a9fE699453059,
        dvnLayerZeroLabs: 0x589dEDbD617e0CBcB916A9223F4d1300c294236b,
        dvnNethermind: 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5,
        confirmations: 15
      });
    }
    if (chainId == 8453) {
      return Chain({
        chainId: 8453,
        eid: 30_184,
        sendLib: 0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2,
        receiveLib: 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf,
        executor: 0x2CCA08ae69E0C44b18a57Ab2A87644234dAebaE4,
        dvnLayerZeroLabs: 0x9e059a54699a285714207b43B055483E78FAac25,
        dvnNethermind: 0xcd37CA043f8479064e10635020c65FfC005d36f6,
        confirmations: 10
      });
    }
    if (chainId == 11_155_111) {
      return Chain({
        chainId: 11_155_111,
        eid: 40_161,
        sendLib: 0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE,
        receiveLib: 0xdAf00F5eE2158dD58E0d3857851c432E34A3A851,
        executor: 0x718B92b5CB0a5552039B593faF724D182A881eDA,
        dvnLayerZeroLabs: 0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193,
        dvnNethermind: 0x68802e01D6321D5159208478f297d7007A7516Ed,
        confirmations: 2
      });
    }
    if (chainId == 84_532) {
      return Chain({
        chainId: 84_532,
        eid: 40_245,
        sendLib: 0xC1868e054425D378095A003EcbA3823a5D0135C9,
        receiveLib: 0x12523de19dc41c91F7d2093E0CFbB76b17012C8d,
        executor: 0x8A3D588D9f6AC041476b094f97FF94ec30169d3D,
        dvnLayerZeroLabs: 0xe1a12515F9AB2764b887bF60B923Ca494EBbB2d6,
        dvnNethermind: 0xd9222CC3Ccd1DF7c070d700EA377D4aDA2B86Eb5,
        confirmations: 2
      });
    }
    revert('LzConfig: no LayerZero config for this chain id');
  }

  /// @notice Every OTHER chain in `chainId`'s family: the peers it is wired to.
  function remotes(uint256 chainId) internal pure returns (Chain[] memory out) {
    uint256[] memory family;
    if (DeployConstants.isMainnet(chainId)) family = DeployConstants.mainnetChains();
    else if (DeployConstants.isTestnet(chainId)) family = DeployConstants.testnetChains();
    else revert('LzConfig: chain id is in neither the mainnet nor the testnet set');

    out = new Chain[](family.length - 1);
    uint256 j;
    for (uint256 i; i < family.length; i++) {
      if (family[i] != chainId) out[j++] = chain(family[i]);
    }
  }

  /// @notice A chain's two required DVNs, sorted ascending as ULN302 requires.
  function requiredDvns(Chain memory c) internal pure returns (address[] memory dvns) {
    dvns = new address[](2);
    (dvns[0], dvns[1]) = c.dvnLayerZeroLabs < c.dvnNethermind
      ? (c.dvnLayerZeroLabs, c.dvnNethermind)
      : (c.dvnNethermind, c.dvnLayerZeroLabs);
  }
}
