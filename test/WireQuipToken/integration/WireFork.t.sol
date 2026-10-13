// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {Constants} from '../../../script/Constants.sol';
import {DeployConstants} from '../../../script/DeployConstants.sol';
import {ICreateX} from '../../../script/ICreateX.sol';
import {LzConfig} from '../../../script/LzConfig.sol';
import {WireQuipTokenBase} from '../../../script/WireQuipTokenBase.sol';
import {QuipToken} from '../../../src/QuipToken.sol';
import {MessagingFee, SendParam} from '@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol';
import {Test} from 'forge-std-1.14.0/Test.sol';

/// @title WireQuipToken Fork Tests
/// @dev Drives the wiring planner against the REAL Base Sepolia endpoint, ULN302
///      libraries, executor and DVNs — so every LzConfig address is exercised by
///      the contracts that would reject a wrong one. Self-skips without
///      API_URL_BASE_SEPOLIA.
contract WireQuipToken_Fork is Test, WireQuipTokenBase {
  uint256 internal constant FORK_BLOCK = 48_000_000;

  address internal constant OWNER = address(0xD31E);

  QuipToken internal token;
  LzConfig.Chain internal local;

  function setUp() public {
    string memory rpc = vm.envOr('API_URL_BASE_SEPOLIA', string(''));
    if (bytes(rpc).length == 0) {
      vm.skip(true);
      return;
    }
    vm.createSelectFork(rpc, FORK_BLOCK);
    local = LzConfig.chain(block.chainid);

    // A remote-chain token at the canonical address, exactly as DeployTestnet
    // would build it on Base Sepolia.
    bytes memory initCode = abi.encodePacked(
      type(QuipToken).creationCode,
      abi.encode(DeployConstants.NAME, DeployConstants.SYMBOL, DeployConstants.TESTNET_LZ_ENDPOINT, OWNER, address(0))
    );
    vm.prank(Constants.DEPLOYER, Constants.DEPLOYER);
    token = QuipToken(ICreateX(Constants.CREATEX).deployCreate3(Constants.tokenSalt(DeployConstants.LABEL), initCode));
  }

  function test_setUp() public view {
    assertEq(address(token), Constants.predictToken(DeployConstants.LABEL));
    assertEq(token.endpoint().eid(), local.eid);
    assertTrue(token.endpoint().isRegisteredLibrary(local.sendLib));
    assertTrue(token.endpoint().isRegisteredLibrary(local.receiveLib));
  }

  function test_plan_freshTokenNeedsEveryStep() public view {
    // One remote (Sepolia): peer, send lib, receive lib, send cfg, receive cfg,
    // plus the enforced-options batch.
    assertEq(_plan(token, local).length, 6);
  }

  function test_plan_isEmptyAfterExecution() public {
    _execute(_plan(token, local));
    assertEq(_plan(token, local).length, 0);
  }

  function test_plan_wiresPeerToSameAddress() public {
    _execute(_plan(token, local));
    assertEq(token.peers(LzConfig.chain(11_155_111).eid), bytes32(uint256(uint160(address(token)))));
  }

  function test_plan_pinsLibraries() public {
    _execute(_plan(token, local));
    uint32 eid = LzConfig.chain(11_155_111).eid;
    assertEq(token.endpoint().getSendLibrary(address(token), eid), local.sendLib);
    assertFalse(token.endpoint().isDefaultSendLibrary(address(token), eid));
    (address lib, bool isDefault) = token.endpoint().getReceiveLibrary(address(token), eid);
    assertEq(lib, local.receiveLib);
    assertFalse(isDefault);
  }

  function test_plan_enforcesReceiveGas() public {
    _execute(_plan(token, local));
    uint32 eid = LzConfig.chain(11_155_111).eid;
    assertEq(token.enforcedOptions(eid, token.SEND()), _enforcedOption());
    assertEq(token.enforcedOptions(eid, token.SEND_AND_CALL()), _enforcedOption());
  }

  /// @dev End to end through the real libraries: a wired token can quote a
  ///      send, which requires the peer, the send library, the executor and
  ///      both DVNs to accept the job.
  function test_plan_wiredTokenQuotesSend() public {
    _execute(_plan(token, local));
    SendParam memory param =
      SendParam(LzConfig.chain(11_155_111).eid, bytes32(uint256(uint160(OWNER))), 1 ether, 1 ether, '', '', '');
    MessagingFee memory fee = token.quoteSend(param, false);
    assertGt(fee.nativeFee, 0);
  }

  function test_plan_revertsWhen_executedByStranger() public {
    Call[] memory calls = _plan(token, local);
    vm.prank(address(0xBAD));
    (bool ok,) = calls[0].to.call(calls[0].data);
    assertFalse(ok);
  }

  function _execute(Call[] memory calls) internal {
    for (uint256 i; i < calls.length; i++) {
      vm.prank(OWNER);
      (bool ok, bytes memory ret) = calls[i].to.call(calls[i].data);
      if (!ok) {
        assembly {
          revert(add(ret, 32), mload(ret))
        }
      }
    }
  }
}
