// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {QuipToken} from '../src/QuipToken.sol';
import {LzConfig} from './LzConfig.sol';
import {ExecutorConfig} from '@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol';
import {UlnConfig} from '@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol';
import {ILayerZeroEndpointV2} from '@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol';
import {SetConfigParam} from '@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol';
import {EnforcedOptionParam} from '@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol';
import {OptionsBuilder} from '@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol';
import {Script} from 'forge-std-1.14.0/Script.sol';

/**
 * @title WireQuipTokenBase
 * @dev Computes the calls that bring one chain's QuipToken in line with
 *      `LzConfig`, for every pathway to the other chains in its family:
 *
 *        1. setPeer             — the remote token (same address on every chain)
 *        2. setSendLibrary      — pin ULN302 instead of following the default
 *        3. setReceiveLibrary   — pin ULN302, no grace period
 *        4. setConfig (send)    — executor + 2-of-2 DVNs, this chain's confirmations
 *        5. setConfig (receive) — the same 2-of-2 DVNs, the REMOTE's confirmations
 *        6. setEnforcedOptions  — minimum lzReceive gas for SEND and SEND_AND_CALL
 *
 *      IDEMPOTENT. Each step is compared against current on-chain state and only
 *      emitted when it differs, so a re-run on a fully wired chain plans zero
 *      calls — which is also how a run verifies itself.
 *
 *      Kept separate from the entrypoint so the fork test drives the exact same
 *      planning code against the real endpoint and libraries.
 */
abstract contract WireQuipTokenBase is Script {
  using OptionsBuilder for bytes;

  struct Call {
    address to;
    bytes data;
    string what;
  }

  uint32 internal constant CONFIG_TYPE_EXECUTOR = 1;
  uint32 internal constant CONFIG_TYPE_ULN = 2;

  /// @dev ULN302's "NONE" marker: opts out of LayerZero's default optional
  ///      DVNs rather than inheriting whatever they are now or become.
  uint8 internal constant NIL_DVN_COUNT = type(uint8).max;

  /// @dev Everything needed to bring `token` on `local` in line with LzConfig.
  function _plan(QuipToken token, LzConfig.Chain memory local) internal view returns (Call[] memory calls) {
    LzConfig.Chain[] memory remotes = LzConfig.remotes(local.chainId);

    // Upper bound: 5 per remote + 1 enforced-options batch.
    calls = new Call[](remotes.length * 5 + 1);
    uint256 n;
    for (uint256 i; i < remotes.length; i++) {
      n = _planPeerAndLibraries(token, local, remotes[i].eid, calls, n);
      n = _planSendConfig(token, local, remotes[i].eid, calls, n);
      n = _planReceiveConfig(token, local, remotes[i], calls, n);
    }
    n = _planEnforcedOptions(token, remotes, calls, n);

    assembly {
      mstore(calls, n)
    }
  }

  /// @dev Steps 1-3 for one remote: peer and pinned libraries.
  function _planPeerAndLibraries(
    QuipToken token,
    LzConfig.Chain memory local,
    uint32 eid,
    Call[] memory calls,
    uint256 n
  ) internal view returns (uint256) {
    ILayerZeroEndpointV2 endpoint = token.endpoint();

    // 1. Peer: the token's own address — CREATE3 put it there on every chain.
    bytes32 peer = bytes32(uint256(uint160(address(token))));
    if (token.peers(eid) != peer) {
      calls[n++] = Call(
        address(token), abi.encodeCall(token.setPeer, (eid, peer)), string.concat('setPeer eid ', vm.toString(eid))
      );
    }

    // 2-3. Libraries. An unset library reports the default, so "matches" is not
    //      enough: require it to be pinned (non-default) as well.
    if (
      endpoint.getSendLibrary(address(token), eid) != local.sendLib
        || endpoint.isDefaultSendLibrary(address(token), eid)
    ) {
      calls[n++] = Call(
        address(endpoint),
        abi.encodeCall(endpoint.setSendLibrary, (address(token), eid, local.sendLib)),
        string.concat('setSendLibrary eid ', vm.toString(eid))
      );
    }
    (address receiveLib, bool receiveIsDefault) = endpoint.getReceiveLibrary(address(token), eid);
    if (receiveLib != local.receiveLib || receiveIsDefault) {
      calls[n++] = Call(
        address(endpoint),
        abi.encodeCall(endpoint.setReceiveLibrary, (address(token), eid, local.receiveLib, 0)),
        string.concat('setReceiveLibrary eid ', vm.toString(eid))
      );
    }
    return n;
  }

  /// @dev Step 4: executor + DVNs on the send library, with OUR confirmations.
  function _planSendConfig(
    QuipToken token,
    LzConfig.Chain memory local,
    uint32 eid,
    Call[] memory calls,
    uint256 n
  ) internal view returns (uint256) {
    ILayerZeroEndpointV2 endpoint = token.endpoint();
    if (
      _executorMatches(endpoint, address(token), local, eid)
        && _ulnMatches(endpoint, address(token), local.sendLib, eid, local, local.confirmations)
    ) return n;

    SetConfigParam[] memory params = new SetConfigParam[](2);
    params[0] =
      SetConfigParam(eid, CONFIG_TYPE_EXECUTOR, abi.encode(ExecutorConfig(LzConfig.MAX_MESSAGE_SIZE, local.executor)));
    params[1] = SetConfigParam(eid, CONFIG_TYPE_ULN, abi.encode(_ulnConfig(local, local.confirmations)));
    calls[n++] = Call(
      address(endpoint),
      abi.encodeCall(endpoint.setConfig, (address(token), local.sendLib, params)),
      string.concat('setConfig send eid ', vm.toString(eid))
    );
    return n;
  }

  /// @dev Step 5: DVNs on the receive library — our DVN deployments, the
  ///      SOURCE chain's confirmations.
  function _planReceiveConfig(
    QuipToken token,
    LzConfig.Chain memory local,
    LzConfig.Chain memory remote,
    Call[] memory calls,
    uint256 n
  ) internal view returns (uint256) {
    ILayerZeroEndpointV2 endpoint = token.endpoint();
    if (_ulnMatches(endpoint, address(token), local.receiveLib, remote.eid, local, remote.confirmations)) return n;

    SetConfigParam[] memory params = new SetConfigParam[](1);
    params[0] = SetConfigParam(remote.eid, CONFIG_TYPE_ULN, abi.encode(_ulnConfig(local, remote.confirmations)));
    calls[n++] = Call(
      address(endpoint),
      abi.encodeCall(endpoint.setConfig, (address(token), local.receiveLib, params)),
      string.concat('setConfig receive eid ', vm.toString(remote.eid))
    );
    return n;
  }

  /// @dev Step 6: one batched setEnforcedOptions covering every remote, emitted
  ///      only if any (eid, msgType) differs.
  function _planEnforcedOptions(
    QuipToken token,
    LzConfig.Chain[] memory remotes,
    Call[] memory calls,
    uint256 n
  ) internal view returns (uint256) {
    bytes memory wanted = _enforcedOption();
    EnforcedOptionParam[] memory options = new EnforcedOptionParam[](remotes.length * 2);
    bool stale;
    for (uint256 i; i < remotes.length; i++) {
      uint32 eid = remotes[i].eid;
      options[i * 2] = EnforcedOptionParam(eid, token.SEND(), wanted);
      options[i * 2 + 1] = EnforcedOptionParam(eid, token.SEND_AND_CALL(), wanted);
      if (
        keccak256(token.enforcedOptions(eid, token.SEND())) != keccak256(wanted)
          || keccak256(token.enforcedOptions(eid, token.SEND_AND_CALL())) != keccak256(wanted)
      ) stale = true;
    }
    if (stale) {
      calls[n++] = Call(address(token), abi.encodeCall(token.setEnforcedOptions, (options)), 'setEnforcedOptions');
    }
    return n;
  }

  /// @dev Type-3 options: `lzReceive` gas, no native drop.
  function _enforcedOption() internal pure returns (bytes memory) {
    return OptionsBuilder.newOptions().addExecutorLzReceiveOption(LzConfig.LZ_RECEIVE_GAS, 0);
  }

  /// @dev 2-of-2 required DVNs on `local`, default optional DVNs explicitly off.
  function _ulnConfig(LzConfig.Chain memory local, uint64 confirmations) internal pure returns (UlnConfig memory) {
    return UlnConfig({
      confirmations: confirmations,
      requiredDVNCount: 2,
      optionalDVNCount: NIL_DVN_COUNT,
      optionalDVNThreshold: 0,
      requiredDVNs: LzConfig.requiredDvns(local),
      optionalDVNs: new address[](0)
    });
  }

  /// @dev Compares the EFFECTIVE config (custom merged over default), which is
  ///      what the library enforces. NIL optional DVNs read back as zero.
  function _ulnMatches(
    ILayerZeroEndpointV2 endpoint,
    address oapp,
    address lib,
    uint32 eid,
    LzConfig.Chain memory local,
    uint64 confirmations
  ) internal view returns (bool) {
    UlnConfig memory got = abi.decode(endpoint.getConfig(oapp, lib, eid, CONFIG_TYPE_ULN), (UlnConfig));
    address[] memory want = LzConfig.requiredDvns(local);
    return got.confirmations == confirmations && got.requiredDVNCount == 2 && got.optionalDVNCount == 0
      && got.requiredDVNs.length == 2 && got.requiredDVNs[0] == want[0] && got.requiredDVNs[1] == want[1];
  }

  function _executorMatches(
    ILayerZeroEndpointV2 endpoint,
    address oapp,
    LzConfig.Chain memory local,
    uint32 eid
  ) internal view returns (bool) {
    ExecutorConfig memory got =
      abi.decode(endpoint.getConfig(oapp, local.sendLib, eid, CONFIG_TYPE_EXECUTOR), (ExecutorConfig));
    return got.executor == local.executor && got.maxMessageSize == LzConfig.MAX_MESSAGE_SIZE;
  }
}
