// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {Constants} from '../../../script/Constants.sol';
import {ConstantsTest} from '../Constants.t.sol';

contract Constants_guardedSalt is ConstantsTest {
  function test_guardedSalt_matchesLiveDeployment() public pure {
    assertEq(Constants.guardedSalt(LIVE_LABEL), LIVE_GUARDED_SALT);
  }

  function test_guardedSalt_isCreateXSenderBranch() public pure {
    string memory label = 'QUIP:QuipToken:v1.0.0';
    bytes32 expected =
      keccak256(abi.encodePacked(bytes32(uint256(uint160(Constants.DEPLOYER))), Constants.tokenSalt(label)));
    assertEq(Constants.guardedSalt(label), expected);
  }
}
