// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {QuipToken} from '../src/QuipToken.sol';
import {Constants} from './Constants.sol';
import {DeployConstants} from './DeployConstants.sol';
import {LzConfig} from './LzConfig.sol';
import {WireQuipTokenBase} from './WireQuipTokenBase.sol';
import {console} from 'forge-std-1.14.0/Script.sol';

interface IEndpointDelegates {
  function delegates(address oapp) external view returns (address);
}

/**
 * @title WireQuipToken
 * @dev Wires the QuipToken on the CONNECTED chain to every other chain in its
 *      family (peers, libraries, DVNs, executor, enforced options). Run once per
 *      chain, after every chain in the family is deployed.
 *
 *      TWO MODES.
 *      - DELEGATE_PK set: broadcasts the calls. The key must be BOTH the token
 *        owner (setPeer, setEnforcedOptions) and the endpoint delegate
 *        (setSendLibrary, setReceiveLibrary, setConfig). Re-plans afterwards and
 *        requires zero remaining calls.
 *      - DELEGATE_PK unset: prints each call's target and calldata, for
 *        execution from the delegate multisig (e.g. a Safe batch). Re-running
 *        after execution must print "0 calls" — that is the verification.
 *
 *      Nothing is read from env except the optional key: the token address is
 *      derived from Constants, and the pathway config is LzConfig.
 *
 * Usage:
 *   make wire RPC=API_URL_SEPOLIA                 # print plan
 *   make wire RPC=API_URL_SEPOLIA BROADCAST=1     # broadcast with DELEGATE_PK
 */
contract WireQuipToken is WireQuipTokenBase {
  function run() external {
    QuipToken token = QuipToken(Constants.predictToken(DeployConstants.LABEL));
    LzConfig.Chain memory local = LzConfig.chain(block.chainid);

    console.log('Chain id:  ', block.chainid);
    console.log('Local eid: ', local.eid);
    console.log('QuipToken: ', address(token));

    // ── Gates. Everything we are about to point the token at must exist here.
    require(address(token).code.length > 0, 'WireQuipToken: QuipToken is not deployed on this chain');
    require(
      address(token.endpoint()) == DeployConstants.lzEndpointFor(block.chainid),
      'WireQuipToken: token endpoint is not the LayerZero EndpointV2 for this chain'
    );
    require(token.endpoint().eid() == local.eid, 'WireQuipToken: endpoint eid does not match LzConfig');
    require(token.endpoint().isRegisteredLibrary(local.sendLib), 'WireQuipToken: send library not registered');
    require(token.endpoint().isRegisteredLibrary(local.receiveLib), 'WireQuipToken: receive library not registered');
    require(local.executor.code.length > 0, 'WireQuipToken: executor has no code');
    require(local.dvnLayerZeroLabs.code.length > 0, 'WireQuipToken: LayerZero Labs DVN has no code');
    require(local.dvnNethermind.code.length > 0, 'WireQuipToken: Nethermind DVN has no code');

    address owner = token.owner();
    address delegate = IEndpointDelegates(address(token.endpoint())).delegates(address(token));
    console.log('Owner:     ', owner);
    console.log('Delegate:  ', delegate);

    Call[] memory calls = _plan(token, local);
    console.log('\nPlanned calls:', calls.length);
    for (uint256 i; i < calls.length; i++) {
      console.log(string.concat('\n[', vm.toString(i), '] ', calls[i].what));
      console.log('  to:  ', calls[i].to);
      console.log('  data:', vm.toString(calls[i].data));
    }
    if (calls.length == 0) {
      console.log('Fully wired. Nothing to do.');
      return;
    }

    uint256 pk = vm.envOr('DELEGATE_PK', uint256(0));
    if (pk == 0) {
      console.log('\nDELEGATE_PK unset: execute the calls above from the owner/delegate, then re-run.');
      return;
    }

    address signer = vm.addr(pk);
    require(signer == owner, 'WireQuipToken: DELEGATE_PK is not the token owner');
    require(signer == delegate, 'WireQuipToken: DELEGATE_PK is not the endpoint delegate');

    vm.startBroadcast(pk);
    for (uint256 i; i < calls.length; i++) {
      (bool ok, bytes memory ret) = calls[i].to.call(calls[i].data);
      if (!ok) {
        assembly {
          revert(add(ret, 32), mload(ret))
        }
      }
    }
    vm.stopBroadcast();

    require(_plan(token, local).length == 0, 'WireQuipToken: config still differs after wiring');
    console.log('\nWired. Re-plan is empty.');
  }
}
