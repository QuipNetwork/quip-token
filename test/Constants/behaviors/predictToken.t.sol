// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {Constants} from '../../../script/Constants.sol';
import {DeployConstants} from '../../../script/DeployConstants.sol';
import {ConstantsTest} from '../Constants.t.sol';

contract Constants_predictToken is ConstantsTest {
  function test_predictToken_matchesLiveDeployment() public pure {
    assertEq(Constants.predictToken(LIVE_LABEL), LIVE_OMNIBUS);
  }

  /// @dev Pins the one canonical address. It moves only if LABEL, DEPLOYER or
  ///      CREATEX changes — each of which this tripwire makes a reviewed edit.
  function test_predictToken_canonicalAddress() public pure {
    assertEq(Constants.predictToken(DeployConstants.LABEL), 0xc24c621b479326a40e21cA7D104ebAB65826a662);
  }

  function test_predictToken_doesNotCollideWithOmnibus() public pure {
    assertTrue(Constants.predictToken(DeployConstants.LABEL) != LIVE_OMNIBUS);
  }
}
