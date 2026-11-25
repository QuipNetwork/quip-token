// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {LzConfig} from '../../../script/LzConfig.sol';
import {WireQuipToken_Fork} from './WireFork.t.sol';
import {UlnConfig} from '@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol';
import {Origin} from '@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol';

contract WireQuipToken_PeerFirstFork is WireQuipToken_Fork {
  function test_peerOnlyOpensAfterTwoDvnReceiveConfig() public {
    uint32 remoteEid = LzConfig.chain(11_155_111).eid;
    Origin memory origin = Origin({srcEid: remoteEid, sender: bytes32(uint256(uint160(address(token)))), nonce: 1});
    assertFalse(token.allowInitializePath(origin));
    (bool defaultLibrary, uint8 initialDvns) = _receiveSecurity(remoteEid);
    assertTrue(defaultLibrary);
    assertEq(initialDvns, 1, 'pinned Base Sepolia default must be one DVN');

    Call[] memory calls = _plan(token, local);
    bool sawPeer;
    for (uint256 i; i < calls.length; i++) {
      vm.prank(OWNER);
      (bool ok, bytes memory ret) = calls[i].to.call(calls[i].data);
      assertTrue(ok, vm.toString(ret));
      if (token.allowInitializePath(origin)) {
        sawPeer = true;
        (, uint8 requiredDvns) = _receiveSecurity(remoteEid);
        if (requiredDvns < 2) {
          emit log('VV-BUG-REPRODUCED: peer active while receive library requires only one DVN');
        }
        assertEq(requiredDvns, 2, 'peer must not open before two-DVN receive config');
      }
    }
    assertTrue(sawPeer);
  }

  function _receiveSecurity(uint32 remoteEid) internal view returns (bool isDefault, uint8 requiredDvns) {
    (address lib, bool defaultLibrary) = token.endpoint().getReceiveLibrary(address(token), remoteEid);
    UlnConfig memory config =
      abi.decode(token.endpoint().getConfig(address(token), lib, remoteEid, CONFIG_TYPE_ULN), (UlnConfig));
    return (defaultLibrary, config.requiredDVNCount);
  }
}
