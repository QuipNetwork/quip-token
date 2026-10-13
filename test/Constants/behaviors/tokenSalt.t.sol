// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {Constants} from '../../../script/Constants.sol';
import {ConstantsTest} from '../Constants.t.sol';

contract Constants_tokenSalt is ConstantsTest {
  function test_tokenSalt_matchesLiveDeployment() public pure {
    assertEq(Constants.tokenSalt(LIVE_LABEL), LIVE_RAW_SALT);
  }

  function test_tokenSalt_leadingBytesAreDeployer() public pure {
    bytes32 salt = Constants.tokenSalt('QUIP:QuipToken:v1.0.0');
    assertEq(address(bytes20(salt)), Constants.DEPLOYER);
  }

  function test_tokenSalt_crossChainFlagIsOff() public pure {
    bytes32 salt = Constants.tokenSalt('QUIP:QuipToken:v1.0.0');
    assertEq(uint8(salt[20]), 0);
  }

  function test_tokenSalt_trailingBytesAreLabelEntropy() public pure {
    string memory label = 'QUIP:QuipToken:v1.0.0';
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes11 tail = bytes11(uint88(uint256(Constants.tokenSalt(label))));
    assertEq(tail, Constants.saltEntropy(label));
    assertEq(tail, bytes11(keccak256(bytes(label))));
  }

  function testFuzz_tokenSalt_distinctLabelsGiveDistinctSalts(string memory a, string memory b) public pure {
    vm.assume(bytes11(keccak256(bytes(a))) != bytes11(keccak256(bytes(b))));
    assertTrue(Constants.tokenSalt(a) != Constants.tokenSalt(b));
  }
}
