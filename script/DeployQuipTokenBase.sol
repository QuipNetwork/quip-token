// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {QuipToken} from '../src/QuipToken.sol';
import {Constants} from './Constants.sol';
import {DeployConstants} from './DeployConstants.sol';
import {ICreateX} from './ICreateX.sol';
import {ILayerZeroEndpointV2} from '@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol';
import {Script, console} from 'forge-std-1.14.0/Script.sol';
import {VmSafe} from 'forge-std-1.14.0/Vm.sol';

/**
 * @title DeployQuipTokenBase
 * @dev Every gate for a QuipToken deployment, shared by DeployMainnet and
 *      DeployTestnet. The subclasses supply only a label and an allowlist.
 *
 *      WHY THIS SCRIPT IS ALL ASSERTIONS. A wrong caller does NOT revert inside
 *      CreateX: it fails the sender-prefix match, takes the permissionless
 *      branch, and deploys SUCCESSFULLY at an unrelated address. Every gate
 *      runs BEFORE `vm.startBroadcast`, so a bad configuration costs nothing.
 *
 *      NOTHING THAT DECIDES THE ADDRESS OR THE SUPPLY COMES FROM THE
 *      ENVIRONMENT. The deployer is `Constants.DEPLOYER`; the label, endpoint
 *      and initial holder are in `DeployConstants`; the chain must be in the
 *      subclass's allowlist. Env supplies only the signing key and the
 *      owner/delegate — neither can move the address or mint.
 *
 *      SAFE / MULTISIG ROUTING IS NOT SUPPORTED, by construction: CreateX keys
 *      its guard off `msg.sender`, so a Safe-executed deploy lands at a
 *      completely different address. Deploy from the ops EOA with the multisig
 *      as QUIP_TOKEN_DELEGATE.
 *
 *      Local rehearsal: bare Anvil has no CreateX — rehearse against a fork of a
 *      chain that does (`make anvil-fork RPC=...`).
 *
 * Environment:
 *   DEPLOYER_PK         - Ops wallet private key. MUST derive Constants.DEPLOYER.
 *   QUIP_TOKEN_DELEGATE - Owner and LayerZero delegate of the token.
 *   EXPECTED_CHAIN_ID   - Optional. Belt-and-braces on top of the allowlist.
 */
abstract contract DeployQuipTokenBase is Script {
  /// @dev The build profile that produces the artifact we ship.
  string internal constant REQUIRED_PROFILE = 'prod';

  /// @notice The salt version label this script deploys under.
  function label() internal pure virtual returns (string memory);

  /// @notice The chain ids this script is allowed to broadcast to.
  function allowedChains() internal pure virtual returns (uint256[] memory);

  /// @notice Human-readable family name, for logs and error messages.
  function family() internal pure virtual returns (string memory);

  function run() external {
    uint256 privateKey = vm.envUint('DEPLOYER_PK');
    address delegate = vm.envAddress('QUIP_TOKEN_DELEGATE');

    address broadcaster = vm.addr(privateKey);
    string memory profile = vm.envOr('FOUNDRY_PROFILE', string('default'));

    string memory versionLabel = label();
    bytes32 rawSalt = Constants.tokenSalt(versionLabel);
    address expectedAddr = Constants.predictToken(versionLabel);

    // Not yet gated by the allowlist, so resolve leniently for logging; the
    // gates below re-derive through the reverting lookups.
    bool listed = _chainAllowed(block.chainid);
    address endpoint = listed ? DeployConstants.lzEndpointFor(block.chainid) : address(0);
    address initialHolder = listed ? DeployConstants.initialHolderFor(block.chainid) : address(0);
    bool home = DeployConstants.isHomeChain(block.chainid);

    // ── 0. Log the whole picture BEFORE the first require.
    console.log('Family:            ', family());
    console.log('Profile:           ', profile);
    console.log('Chain id:          ', block.chainid);
    console.log('Home chain:        ', home);
    console.log('Version label:     ', versionLabel);
    console.log('Broadcaster (PK):  ', broadcaster);
    console.log('tx.origin:         ', tx.origin);
    console.log('Constants.DEPLOYER:', Constants.DEPLOYER);
    console.log('Expected QuipToken:', expectedAddr);
    console.log('Delegate / owner:  ', delegate);
    console.log('LZ endpoint:       ', endpoint);
    console.log('Initial holder:    ', initialHolder);
    console.log('Raw salt:');
    console.logBytes32(rawSalt);
    console.log('Guarded salt:');
    console.logBytes32(Constants.guardedSalt(versionLabel));

    // ── 1. Build provenance. Catches a dev-profile artifact reaching a chain.
    require(
      keccak256(bytes(profile)) == keccak256(bytes(REQUIRED_PROFILE)),
      'DeployQuipToken: FOUNDRY_PROFILE must be prod (use the make deploy targets)'
    );

    // ── 2. Signer identity. THE gate: any other key deploys a different,
    //       unadvertised token and still satisfies every post-condition.
    require(broadcaster == Constants.DEPLOYER, 'DeployQuipToken: DEPLOYER_PK does not derive Constants.DEPLOYER');

    // ── 3. Secondary signer gate for --sender / --unlocked / hardware paths.
    if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
      require(tx.origin == Constants.DEPLOYER, 'DeployQuipToken: tx.origin is not Constants.DEPLOYER');
    }

    // ── 4. Chain allowlist. Stops an rpc-alias typo from burning a mainnet
    //       address on a testnet and splitting the family.
    require(listed, string.concat('DeployQuipToken: chain id not in the ', family(), ' allowlist'));

    uint256 expectedChainId = vm.envOr('EXPECTED_CHAIN_ID', uint256(0));
    if (expectedChainId != 0) {
      require(block.chainid == expectedChainId, 'DeployQuipToken: connected to the wrong chain');
    }

    // ── 5. Supply. Exactly one chain per family mints, and it must mint to a
    //       real recipient. A non-zero holder on a remote chain would be a
    //       second supply; a zero holder on the home chain would be no supply.
    if (home) {
      require(initialHolder != address(0), 'DeployQuipToken: home chain needs a non-zero initial holder');
    } else {
      require(initialHolder == address(0), 'DeployQuipToken: remote chain must not mint');
    }

    // ── 6. Constructor args. The endpoint is an immutable and every OFT path
    //       goes through it, so probe the ABI, not just the code.
    require(delegate != address(0), 'DeployQuipToken: QUIP_TOKEN_DELEGATE must be non-zero');
    require(endpoint.code.length > 0, 'DeployQuipToken: LayerZero endpoint has no code on this chain');
    try ILayerZeroEndpointV2(endpoint).eid() returns (uint32 eid) {
      console.log('LZ eid:            ', eid);
    } catch {
      revert('DeployQuipToken: LayerZero endpoint does not implement eid()');
    }

    // ── 7. Factory presence + derivation agreement: our solady CREATE3 math
    //       and the on-chain factory derive the SAME address.
    require(Constants.CREATEX.code.length > 0, 'DeployQuipToken: CreateX not deployed on this chain');
    require(
      ICreateX(Constants.CREATEX).computeCreate3Address(Constants.guardedSalt(versionLabel)) == expectedAddr,
      'DeployQuipToken: CreateX disagrees with the local CREATE3 prediction'
    );

    // ── 8. Occupancy. A CREATE3 address ignores init code, so "has code" says
    //       nothing about WHAT is there. Never skip silently.
    if (expectedAddr.code.length > 0) {
      _requireOurTokenAt(expectedAddr, delegate, endpoint);
      console.log('\nQuipToken already deployed and verified at this address. Nothing to do.');
      return;
    }

    bytes memory bytecode = abi.encodePacked(
      type(QuipToken).creationCode,
      abi.encode(DeployConstants.NAME, DeployConstants.SYMBOL, endpoint, delegate, initialHolder)
    );

    vm.startBroadcast(privateKey);
    address deployed = ICreateX(Constants.CREATEX).deployCreate3(rawSalt, bytecode);
    vm.stopBroadcast();

    // Backstop for any branch divergence between our mirror and the factory.
    require(deployed == expectedAddr, 'DeployQuipToken: deployed address does not match the prediction');
    _requireOurTokenAt(deployed, delegate, endpoint);
    if (home) {
      require(
        QuipToken(deployed).balanceOf(initialHolder) == QuipToken(deployed).TOTAL_SUPPLY(),
        'DeployQuipToken: initial holder did not receive the full supply'
      );
    } else {
      require(QuipToken(deployed).totalSupply() == 0, 'DeployQuipToken: remote chain minted supply');
    }
    console.log('QuipToken deployed at:', deployed);
    console.log('Next: wire peers / enforced options / DVNs per pathway from the delegate.');
  }

  /// @dev Asserts the contract at `addr` really is OUR token, using values fixed
  ///      at construction. `owner()` is a warning only: ownership is
  ///      transferable, so a legitimate re-run after a handover must not revert.
  function _requireOurTokenAt(address addr, address expectedOwner, address expectedEndpoint) internal view {
    QuipToken existing = QuipToken(addr);

    // A non-OFT contract fails this staticcall; catch it for a legible message.
    try existing.endpoint() returns (ILayerZeroEndpointV2 ep) {
      require(address(ep) == expectedEndpoint, 'DeployQuipToken: address occupied - endpoint mismatch');
    } catch {
      revert('DeployQuipToken: address occupied by a contract that is not a QuipToken');
    }
    require(
      keccak256(bytes(existing.name())) == keccak256(bytes(DeployConstants.NAME)),
      'DeployQuipToken: address occupied - name mismatch'
    );
    require(
      keccak256(bytes(existing.symbol())) == keccak256(bytes(DeployConstants.SYMBOL)),
      'DeployQuipToken: address occupied - symbol mismatch'
    );
    require(existing.token() == addr, 'DeployQuipToken: address occupied - not a native OFT');

    address currentOwner = existing.owner();
    if (currentOwner != expectedOwner) {
      console.log('WARNING: on-chain owner differs from QUIP_TOKEN_DELEGATE (transferred?):', currentOwner);
    }
  }

  function _chainAllowed(uint256 chainId) private pure returns (bool) {
    uint256[] memory chains = allowedChains();
    for (uint256 i; i < chains.length; i++) {
      if (chains[i] == chainId) return true;
    }
    return false;
  }
}
