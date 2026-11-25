// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {LzConfig} from '../../../script/LzConfig.sol';
import {WireQuipToken_Fork} from './WireFork.t.sol';
import {
  ExecutorConfig,
  SetDefaultExecutorConfigParam
} from '@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol';
import {SetDefaultUlnConfigParam, UlnConfig} from '@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol';

interface VVRealUlnDefaults {
  function owner() external view returns (address);
  function setDefaultUlnConfigs(SetDefaultUlnConfigParam[] calldata params) external;
  function getAppUlnConfig(address oapp, uint32 eid) external view returns (UlnConfig memory);
}

interface VVRealSendDefaults {
  function owner() external view returns (address);
  function setDefaultExecutorConfigs(SetDefaultExecutorConfigParam[] calldata params) external;
  function executorConfigs(address oapp, uint32 eid) external view returns (uint32, address);
}

contract WireQuipToken_ExplicitPinFork is WireQuipToken_Fork {
  function test_matchingRealDefaultsMustStoreAppSecurityPins() public {
    uint32 eid = LzConfig.chain(11_155_111).eid;
    _setRealDefaults(eid, true);
    _execute(_plan(token, local));
    UlnConfig memory rawSend = VVRealUlnDefaults(local.sendLib).getAppUlnConfig(address(token), eid);
    UlnConfig memory rawReceive = VVRealUlnDefaults(local.receiveLib).getAppUlnConfig(address(token), eid);
    (uint32 rawSize, address rawExecutor) = VVRealSendDefaults(local.sendLib).executorConfigs(address(token), eid);

    _setRealDefaults(eid, false);
    UlnConfig memory effectiveSend =
      abi.decode(token.endpoint().getConfig(address(token), local.sendLib, eid, CONFIG_TYPE_ULN), (UlnConfig));
    UlnConfig memory effectiveReceive =
      abi.decode(token.endpoint().getConfig(address(token), local.receiveLib, eid, CONFIG_TYPE_ULN), (UlnConfig));
    ExecutorConfig memory effectiveExecutor = abi.decode(
      token.endpoint().getConfig(address(token), local.sendLib, eid, CONFIG_TYPE_EXECUTOR), (ExecutorConfig)
    );
    if (
      effectiveSend.requiredDVNCount != 2 || effectiveReceive.requiredDVNCount != 2
        || effectiveExecutor.executor != local.executor
    ) {
      emit log('VV-BUG-REPRODUCED: real ULN302 defaults changed effective app security after wiring');
    }
    assertEq(rawSend.requiredDVNCount, 2, 'send ULN override missing');
    assertEq(rawReceive.requiredDVNCount, 2, 'receive ULN override missing');
    assertEq(rawSize, LzConfig.MAX_MESSAGE_SIZE, 'executor override missing');
    assertEq(rawExecutor, local.executor, 'executor address override missing');
    assertEq(effectiveSend.requiredDVNCount, 2);
    assertEq(effectiveReceive.requiredDVNCount, 2);
    assertEq(effectiveExecutor.executor, local.executor);
    assertEq(_plan(token, local).length, 0);
  }

  function _setRealDefaults(uint32 eid, bool desired) internal {
    address[] memory dvns = desired ? LzConfig.requiredDvns(local) : new address[](1);
    if (!desired) dvns[0] = local.dvnLayerZeroLabs;
    UlnConfig memory uln = UlnConfig({
      confirmations: local.confirmations,
      requiredDVNCount: uint8(dvns.length),
      optionalDVNCount: 0,
      optionalDVNThreshold: 0,
      requiredDVNs: dvns,
      optionalDVNs: new address[](0)
    });
    SetDefaultUlnConfigParam[] memory ulnParams = new SetDefaultUlnConfigParam[](1);
    ulnParams[0] = SetDefaultUlnConfigParam(eid, uln);
    vm.prank(VVRealUlnDefaults(local.sendLib).owner());
    VVRealUlnDefaults(local.sendLib).setDefaultUlnConfigs(ulnParams);
    vm.prank(VVRealUlnDefaults(local.receiveLib).owner());
    VVRealUlnDefaults(local.receiveLib).setDefaultUlnConfigs(ulnParams);

    SetDefaultExecutorConfigParam[] memory executorParams = new SetDefaultExecutorConfigParam[](1);
    executorParams[0] = SetDefaultExecutorConfigParam(
      eid, ExecutorConfig(LzConfig.MAX_MESSAGE_SIZE, desired ? local.executor : address(0xBAD))
    );
    vm.prank(VVRealSendDefaults(local.sendLib).owner());
    VVRealSendDefaults(local.sendLib).setDefaultExecutorConfigs(executorParams);
  }
}
