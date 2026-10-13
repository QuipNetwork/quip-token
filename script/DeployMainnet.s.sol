// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {DeployConstants} from './DeployConstants.sol';
import {DeployQuipTokenBase} from './DeployQuipTokenBase.sol';

/**
 * @title DeployMainnet
 * @dev Deploys QuipToken to a MAINNET chain under `LABEL`.
 *
 *      Deliberately separate from the other family's script so a deploy cannot
 *      pick up the other family's endpoint and supply holder by passing the
 *      wrong argument — there is no argument. The allowlist in the base then catches the remaining error, an
 *      rpc alias pointing somewhere else entirely.
 */
contract DeployMainnet is DeployQuipTokenBase {
  function label() internal pure override returns (string memory) {
    return DeployConstants.LABEL;
  }

  function allowedChains() internal pure override returns (uint256[] memory) {
    return DeployConstants.mainnetChains();
  }

  function family() internal pure override returns (string memory) {
    return 'mainnet';
  }
}
