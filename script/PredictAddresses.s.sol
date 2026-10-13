// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {Constants} from './Constants.sol';
import {DeployConstants} from './DeployConstants.sol';
import {Script, console} from 'forge-std-1.14.0/Script.sol';

/// @title PredictAddresses
/// @dev Prints the QuipToken address on every chain. Pure offline math: no RPC.
///      Usage: forge script script/PredictAddresses.s.sol
contract PredictAddresses is Script {
  function run() external pure {
    console.log('Label:', DeployConstants.LABEL);
    console.log('QuipToken (every chain):', Constants.predictToken(DeployConstants.LABEL));
  }
}
