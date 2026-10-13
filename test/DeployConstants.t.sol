// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {DeployConstants} from '../script/DeployConstants.sol';
import {Test} from 'forge-std-1.14.0/Test.sol';

/// @dev Tripwires on the per-chain supply routing: exactly one chain per family
///      mints, and every listed remote chain gets `address(0)`.
contract DeployConstantsTest is Test {
  function test_initialHolderFor_onlyHomeChainsMint() public pure {
    uint256[] memory mainnets = DeployConstants.mainnetChains();
    uint256 minting;
    for (uint256 i; i < mainnets.length; i++) {
      if (DeployConstants.isHomeChain(mainnets[i])) minting++;
      else assertEq(DeployConstants.initialHolderFor(mainnets[i]), address(0));
    }
    assertEq(minting, 1, 'mainnet family must have exactly one home chain');

    uint256[] memory testnets = DeployConstants.testnetChains();
    minting = 0;
    for (uint256 i; i < testnets.length; i++) {
      if (DeployConstants.isHomeChain(testnets[i])) minting++;
      else assertEq(DeployConstants.initialHolderFor(testnets[i]), address(0));
    }
    assertEq(minting, 1, 'testnet family must have exactly one home chain');
  }

  function test_homeChainsAreInTheirFamilies() public pure {
    assertTrue(DeployConstants.isMainnet(DeployConstants.MAINNET_HOME_CHAIN));
    assertTrue(DeployConstants.isTestnet(DeployConstants.TESTNET_HOME_CHAIN));
  }

  function test_testnetHomeChainMintsToHolder() public pure {
    assertEq(
      DeployConstants.initialHolderFor(DeployConstants.TESTNET_HOME_CHAIN), DeployConstants.TESTNET_INITIAL_HOLDER
    );
    assertTrue(DeployConstants.TESTNET_INITIAL_HOLDER != address(0));
  }

  function test_lzEndpointFor_perFamily() public pure {
    assertEq(DeployConstants.lzEndpointFor(1), DeployConstants.MAINNET_LZ_ENDPOINT);
    assertEq(DeployConstants.lzEndpointFor(84_532), DeployConstants.TESTNET_LZ_ENDPOINT);
  }

  function test_initialHolderFor_revertsWhen_chainUnlisted() public {
    vm.expectRevert(bytes('DeployConstants: chain id is in neither the mainnet nor the testnet set'));
    this.initialHolderFor(31_337);
  }

  function initialHolderFor(uint256 chainId) external pure returns (address) {
    return DeployConstants.initialHolderFor(chainId);
  }
}
