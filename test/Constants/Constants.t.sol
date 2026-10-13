// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {Constants} from '../../script/Constants.sol';
import {Test} from 'forge-std-1.14.0/Test.sol';

/// @title Constants Base Test
/// @dev QuipToken has no live deployment yet, so this suite anchors the salt math
///      to one that does: quip-swap-solidity's Omnibus on Base Sepolia, deployed
///      through the same CreateX factory by the same ops EOA with the same
///      salt scheme. Those literals are transcribed from the chain, so a change
///      to the composition fails against reality rather than agreeing with
///      itself.
contract ConstantsTest is Test {
  /// @dev Live quip-swap Omnibus (Base Sepolia, chain id 84532).
  address public constant LIVE_OMNIBUS = 0xf780Fc9C066D824bFF85758E381A3919B1817f09;

  /// @dev The raw salt in that deployment's `deployCreate3` calldata.
  bytes32 public constant LIVE_RAW_SALT = 0xc68b64770da7914deb0ef238b048a0bf3b5f6a260035932c1cb05b05751c5da2;

  /// @dev The guarded salt CreateX derived from it.
  bytes32 public constant LIVE_GUARDED_SALT = 0x320d32719344a6801119cc535b8acada9f02ba39034b1b4440f460dcf3973912;

  /// @dev The label the live Omnibus was deployed under.
  string public constant LIVE_LABEL = 'QUIP:Omnibus:v1.0.0-alpha.2';

  /// @dev Pins the compiled-in constants: the only inputs to the token address
  ///      besides the label.
  function test_setUp() public pure virtual {
    assertEq(Constants.CREATEX, 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed, 'CreateX singleton changed');
    assertEq(Constants.DEPLOYER, 0xc68B64770Da7914DEb0EF238b048a0Bf3B5f6A26, 'DEPLOYER changed');
  }
}
