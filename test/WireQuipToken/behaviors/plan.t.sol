// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {LzConfig} from '../../../script/LzConfig.sol';
import {WireQuipTokenBase} from '../../../script/WireQuipTokenBase.sol';
import {QuipToken} from '../../../src/QuipToken.sol';
import {
  ExecutorConfig,
  SendLibBase,
  SetDefaultExecutorConfigParam
} from '@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol';
import {
  SetDefaultUlnConfigParam,
  UlnBase,
  UlnConfig
} from '@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol';
import {
  ILayerZeroEndpointV2,
  Origin
} from '@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol';
import {SetConfigParam} from '@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol';
import {TestHelperOz5} from '@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol';

/// @dev Runs the production planner against LayerZero's local EndpointV2/ULN302
/// test contracts (their production configuration implementations). No RPC is needed to exercise defaults merging or delegate checks.
contract WireQuipToken__plan is TestHelperOz5, WireQuipTokenBase {
  address internal constant OWNER = address(0xD31E);
  QuipToken internal token;
  LzConfig.Chain internal local;
  uint32 internal remoteEid;

  function setUp() public override {
    super.setUp();
    setUpEndpoints(2, LibraryType.UltraLightNode);
    local = LzConfig.chain(84_532);
    local.sendLib = endpointSetup.sendLibs[0];
    local.receiveLib = endpointSetup.receiveLibs[0];
    local.executor = address(0xE10);
    local.dvnLayerZeroLabs = address(0x1001);
    local.dvnNethermind = address(0x1002);
    remoteEid = LzConfig.chain(11_155_111).eid;
    _setDefaults(false);
    endpointSetup.endpointList[0].setDefaultSendLibrary(remoteEid, local.sendLib);
    endpointSetup.endpointList[0].setDefaultReceiveLibrary(remoteEid, local.receiveLib, 0);
    token = new QuipToken('Quip', 'QUIP', endpoints[1], OWNER, address(0));
  }

  function test_plan_pinsMatchingDefaultsAgainstLaterChanges() public {
    _setDefaults(true);
    _execute(_plan(token, local));
    _assertPinned(local.sendLib);
    _assertPinned(local.receiveLib);
    (uint32 size, address executor) = SendLibBase(local.sendLib).executorConfigs(address(token), remoteEid);
    assertEq(size, LzConfig.MAX_MESSAGE_SIZE);
    assertEq(executor, local.executor);

    _setDefaults(false);
    _assertEffective(local.sendLib);
    _assertEffective(local.receiveLib);
    ExecutorConfig memory effective = abi.decode(
      token.endpoint().getConfig(address(token), local.sendLib, remoteEid, CONFIG_TYPE_EXECUTOR), (ExecutorConfig)
    );
    assertEq(effective.maxMessageSize, LzConfig.MAX_MESSAGE_SIZE);
    assertEq(effective.executor, local.executor);
    assertEq(_plan(token, local).length, 0);
  }

  function test_plan_opensPeerOnlyAfterPinnedReceiveSecurity() public {
    Origin memory origin = Origin(remoteEid, bytes32(uint256(uint160(address(token)))), 1);
    assertFalse(token.allowInitializePath(origin));
    Call[] memory calls = _plan(token, local);
    assertEq(calls.length, 6);
    bool sawPeer;
    for (uint256 i; i < calls.length; i++) {
      _executeCall(calls[i]);
      if (token.allowInitializePath(origin)) {
        sawPeer = true;
        (address lib, bool isDefault) = token.endpoint().getReceiveLibrary(address(token), remoteEid);
        assertFalse(isDefault, 'peer opened before receive library pin');
        assertEq(lib, local.receiveLib);
        _assertPinned(lib);
        _assertEffective(lib);
      }
    }
    assertTrue(sawPeer);
    assertEq(_plan(token, local).length, 0);
  }

  function test_plan_isIdempotentAndRepairsAnExplicitOverride() public {
    _execute(_plan(token, local));
    assertEq(_plan(token, local).length, 0);
    // A different explicit executor must be repaired even with pinned ULNs.
    SetConfigParam[] memory params = new SetConfigParam[](1);
    params[0] = SetConfigParam(remoteEid, CONFIG_TYPE_EXECUTOR, abi.encode(ExecutorConfig(500, address(0xBAD))));
    address endpoint = address(token.endpoint());
    vm.prank(OWNER);
    ILayerZeroEndpointV2(endpoint).setConfig(address(token), local.sendLib, params);
    Call[] memory repair = _plan(token, local);
    assertEq(repair.length, 1);
    _execute(repair);
    assertEq(_plan(token, local).length, 0);
  }

  function _assertPinned(address lib) internal view {
    UlnConfig memory cfg = UlnBase(lib).getAppUlnConfig(address(token), remoteEid);
    assertEq(cfg.confirmations, 2);
    assertEq(cfg.requiredDVNCount, 2, 'app-specific required DVNs missing');
    assertEq(cfg.requiredDVNs, LzConfig.requiredDvns(local));
    assertEq(cfg.optionalDVNCount, NIL_DVN_COUNT);
    assertEq(cfg.optionalDVNThreshold, 0);
    assertEq(cfg.optionalDVNs.length, 0);
  }

  function _assertEffective(address lib) internal view {
    UlnConfig memory cfg =
      abi.decode(token.endpoint().getConfig(address(token), lib, remoteEid, CONFIG_TYPE_ULN), (UlnConfig));
    assertEq(cfg.confirmations, 2);
    assertEq(cfg.requiredDVNCount, 2);
    assertEq(cfg.requiredDVNs, LzConfig.requiredDvns(local));
    assertEq(cfg.optionalDVNCount, 0);
    assertEq(cfg.optionalDVNThreshold, 0);
    assertEq(cfg.optionalDVNs.length, 0);
  }

  function _setDefaults(bool desired) internal {
    address[] memory dvns = desired ? LzConfig.requiredDvns(local) : new address[](1);
    if (!desired) dvns[0] = local.dvnLayerZeroLabs;
    address[] memory optional = new address[](desired ? 0 : 1);
    if (!desired) optional[0] = address(0x2001);
    UlnConfig memory cfg = UlnConfig({
      confirmations: desired ? 2 : 1,
      requiredDVNCount: uint8(dvns.length),
      optionalDVNCount: uint8(optional.length),
      optionalDVNThreshold: desired ? 0 : 1,
      requiredDVNs: dvns,
      optionalDVNs: optional
    });
    SetDefaultUlnConfigParam[] memory uln = new SetDefaultUlnConfigParam[](1);
    uln[0] = SetDefaultUlnConfigParam(remoteEid, cfg);
    UlnBase(local.sendLib).setDefaultUlnConfigs(uln);
    UlnBase(local.receiveLib).setDefaultUlnConfigs(uln);
    SetDefaultExecutorConfigParam[] memory executor = new SetDefaultExecutorConfigParam[](1);
    executor[0] = SetDefaultExecutorConfigParam(
      remoteEid, ExecutorConfig(desired ? LzConfig.MAX_MESSAGE_SIZE : 500, desired ? local.executor : address(0xBAD))
    );
    SendLibBase(local.sendLib).setDefaultExecutorConfigs(executor);
  }

  function _execute(Call[] memory calls) internal {
    for (uint256 i; i < calls.length; i++) {
      _executeCall(calls[i]);
    }
  }

  function _executeCall(Call memory call_) internal {
    vm.prank(OWNER);
    (bool ok, bytes memory ret) = call_.to.call(call_.data);
    if (!ok) {
      assembly { revert(add(ret, 32), mload(ret)) }
    }
  }
}
