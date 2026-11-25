// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {QuipToken} from '../../../src/QuipToken.sol';
import {UlnConfig} from '@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol';
import {ILayerZeroEndpointV2} from '@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol';
import {SetConfigParam} from '@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol';
import {TestHelperOz5} from '@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol';

interface IDelegateSlot {
  function delegates(address oapp) external view returns (address);
}

contract QuipToken_renounceOwnership is TestHelperOz5 {
  address internal constant OWNER = address(0xA11CE);
  QuipToken internal token;
  ILayerZeroEndpointV2 internal endpoint;
  address internal receiveLib;

  function setUp() public override {
    super.setUp();
    setUpEndpoints(2, LibraryType.UltraLightNode);
    token = new QuipToken('Quip', 'QUIP', endpoints[1], OWNER, address(0));
    endpoint = token.endpoint();
    receiveLib = endpointSetup.receiveLibs[0];
  }

  function test_renounceOwnership_revokesEndpointConfiguration() public {
    SetConfigParam[] memory strong = new SetConfigParam[](1);
    strong[0] = SetConfigParam(2, 2, abi.encode(_uln(2, 100)));
    vm.prank(OWNER);
    endpoint.setConfig(address(token), receiveLib, strong);
    UlnConfig memory beforeConfig = abi.decode(endpoint.getConfig(address(token), receiveLib, 2, 2), (UlnConfig));
    assertEq(beforeConfig.requiredDVNCount, 2);

    vm.prank(OWNER);
    token.renounceOwnership();
    assertEq(token.owner(), address(0));

    SetConfigParam[] memory weak = new SetConfigParam[](1);
    weak[0] = SetConfigParam(2, 2, abi.encode(_uln(1, 1)));
    bool outsiderChanged;
    vm.prank(address(0xB0B));
    try endpoint.setConfig(address(token), receiveLib, weak) {
      outsiderChanged = true;
    } catch {}
    assertFalse(outsiderChanged, 'unrelated address must not control endpoint');
    bool changed;
    vm.prank(OWNER);
    try endpoint.setConfig(address(token), receiveLib, weak) {
      changed = true;
    } catch {}
    if (changed) {
      UlnConfig memory afterConfig = abi.decode(endpoint.getConfig(address(token), receiveLib, 2, 2), (UlnConfig));
      assertEq(afterConfig.requiredDVNCount, 1);
      assertEq(afterConfig.confirmations, 1);
      emit log('VV-BUG-REPRODUCED: former owner weakened receive security after renounce');
    }
    assertFalse(changed, 'former owner must lose endpoint configuration power');
    assertEq(IDelegateSlot(address(endpoint)).delegates(address(token)), address(0));
  }

  function test_renounceOwnership_revertsWhen_notOwner() public {
    vm.prank(address(0xB0B));
    vm.expectRevert();
    token.renounceOwnership();
    assertEq(token.owner(), OWNER);
    assertEq(IDelegateSlot(address(endpoint)).delegates(address(token)), OWNER);
  }

  function test_renounceOwnership_clearsASeparateDelegate() public {
    address delegate = address(0xDE1E);
    vm.prank(OWNER);
    token.setDelegate(delegate);
    assertEq(IDelegateSlot(address(endpoint)).delegates(address(token)), delegate);
    vm.prank(OWNER);
    token.renounceOwnership();
    assertEq(token.owner(), address(0));
    assertEq(IDelegateSlot(address(endpoint)).delegates(address(token)), address(0));
    assertEq(token.totalSupply(), 0);
  }

  function test_renounceOwnership_revertsWhen_delegateRevocationFails() public {
    vm.mockCallRevert(address(endpoint), abi.encodeCall(endpoint.setDelegate, (address(0))), 'endpoint failure');
    vm.prank(OWNER);
    vm.expectRevert(bytes('endpoint failure'));
    token.renounceOwnership();
    assertEq(token.owner(), OWNER);
    assertEq(IDelegateSlot(address(endpoint)).delegates(address(token)), OWNER);
  }

  function _uln(uint8 count, uint64 confirmations) internal pure returns (UlnConfig memory config) {
    address[] memory required = new address[](count);
    required[0] = address(0x1001);
    if (count == 2) required[1] = address(0x1002);
    config = UlnConfig({
      confirmations: confirmations,
      requiredDVNCount: count,
      optionalDVNCount: type(uint8).max,
      optionalDVNThreshold: 0,
      requiredDVNs: required,
      optionalDVNs: new address[](0)
    });
  }
}
