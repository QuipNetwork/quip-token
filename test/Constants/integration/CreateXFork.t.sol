// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {Constants} from '../../../script/Constants.sol';
import {DeployConstants} from '../../../script/DeployConstants.sol';
import {ICreateX} from '../../../script/ICreateX.sol';
import {QuipToken} from '../../../src/QuipToken.sol';
import {Test} from 'forge-std-1.14.0/Test.sol';

/// @title CreateX Permissioned-Guard Fork Tests
/// @dev The ONLY tests that run the real CreateX bytecode and the real LayerZero
///      testnet endpoint. Everything else checks our mirror of the guard against
///      literals, which documents CreateX rather than executing it.
///
///      Run before any broadcast: `make test-fork`.
///
///      GATING. CI has no RPC secrets, so `setUp` self-skips when
///      API_URL_BASE_SEPOLIA is unset. CI still compiles the file, so it cannot
///      silently rot. The env var is read directly rather than through
///      `[rpc_endpoints]`, because the alias hard-errors when unset.
contract Constants_CreateXFork is Test {
  /// @dev Pinned so runs are deterministic and cached after the first fetch.
  uint256 internal constant FORK_BLOCK = 48_000_000;

  uint256 internal constant FORK_CHAIN_ID = 84_532; // Base Sepolia

  /// @dev An unclaimed label: the deploy tests must not consume the real one.
  string internal constant TEST_LABEL = 'QUIP:QuipToken:fork-test-only';

  address internal constant STRANGER = address(0xBAD);
  address internal constant HOLDER = address(0xF00D);

  ICreateX internal createX = ICreateX(Constants.CREATEX);

  function setUp() public {
    string memory rpc = vm.envOr('API_URL_BASE_SEPOLIA', string(''));
    if (bytes(rpc).length == 0) {
      vm.skip(true);
      return;
    }
    vm.createSelectFork(rpc, FORK_BLOCK);
  }

  function test_setUp() public view {
    assertEq(block.chainid, FORK_CHAIN_ID, 'fork is not Base Sepolia');
    assertGt(Constants.CREATEX.code.length, 0, 'CreateX has no code on this fork');
    assertGt(DeployConstants.TESTNET_LZ_ENDPOINT.code.length, 0, 'LayerZero endpoint has no code on this fork');
  }

  /// @dev The cross-check the deploy script performs at gate 7.
  function test_computeCreate3Address_agreesWithLocalPrediction() public view {
    assertEq(
      createX.computeCreate3Address(Constants.guardedSalt(TEST_LABEL)),
      Constants.predictToken(TEST_LABEL),
      'CreateX disagrees with the local CREATE3 prediction'
    );
  }

  function test_deployCreate3_deployerLandsAtPrediction() public {
    address deployed = _deployAs(Constants.DEPLOYER, HOLDER);
    assertEq(deployed, Constants.predictToken(TEST_LABEL));

    QuipToken token = QuipToken(deployed);
    assertEq(token.name(), DeployConstants.NAME);
    assertEq(token.symbol(), DeployConstants.SYMBOL);
    assertEq(address(token.endpoint()), DeployConstants.TESTNET_LZ_ENDPOINT);
    assertEq(token.balanceOf(HOLDER), token.TOTAL_SUPPLY());
  }

  /// @dev Address is independent of constructor args: a remote-chain build
  ///      (no mint) lands at the same address as the home-chain build.
  function test_deployCreate3_addressIgnoresConstructorArgs() public {
    uint256 snapshot = vm.snapshotState();
    address home = _deployAs(Constants.DEPLOYER, HOLDER);
    vm.revertToState(snapshot);
    address remote = _deployAs(Constants.DEPLOYER, address(0));

    assertEq(home, remote);
    assertEq(QuipToken(remote).totalSupply(), 0);
  }

  /// @dev A wrong signer does NOT revert: it lands somewhere else, and the
  ///      canonical address stays empty. This is why the deploy script gates on
  ///      the signer before broadcasting.
  function test_senderGuard_strangerLandsElsewhere_canonicalUntouched() public {
    address deployed = _deployAs(STRANGER, HOLDER);
    address canonical = Constants.predictToken(TEST_LABEL);

    assertTrue(deployed != canonical, 'stranger claimed the canonical address');
    assertEq(canonical.code.length, 0, 'canonical address was occupied by a stranger');
  }

  function _deployAs(address sender, address holder) internal returns (address) {
    bytes memory initCode = abi.encodePacked(
      type(QuipToken).creationCode,
      abi.encode(
        DeployConstants.NAME, DeployConstants.SYMBOL, DeployConstants.TESTNET_LZ_ENDPOINT, Constants.DEPLOYER, holder
      )
    );
    vm.prank(sender, sender);
    return createX.deployCreate3(Constants.tokenSalt(TEST_LABEL), initCode);
  }
}
