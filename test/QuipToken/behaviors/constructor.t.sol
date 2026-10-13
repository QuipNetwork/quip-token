// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {QuipToken} from '../../../src/QuipToken.sol';
import {QuipTokenTest} from '../QuipToken.t.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract QuipToken_constructor is QuipTokenTest {
  function test_constructor_setsMetadata() public view {
    assertEq(aToken.name(), NAME);
    assertEq(aToken.symbol(), SYMBOL);
    assertEq(aToken.decimals(), 18);
  }

  function test_constructor_totalSupplyIsOneBillion() public view {
    assertEq(aToken.TOTAL_SUPPLY(), 1_000_000_000 ether);
  }

  function test_constructor_homeChainMintsFullSupplyToInitialHolder() public {
    QuipToken token = _deployQuipToken(endpoints[A_EID], BOB);
    assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    assertEq(token.balanceOf(BOB), token.TOTAL_SUPPLY());
  }

  function test_constructor_remoteChainMintsNothing() public {
    QuipToken token = _deployQuipToken(endpoints[B_EID], address(0));
    assertEq(token.totalSupply(), 0);
  }

  function test_constructor_emitsMintTransfer() public {
    vm.expectEmit(true, true, false, true);
    emit IERC20.Transfer(address(0), BOB, 1_000_000_000 ether);
    _deployQuipToken(endpoints[A_EID], BOB);
  }

  function test_constructor_setsOwnerAndDelegate() public view {
    assertEq(aToken.owner(), OWNER);
    assertEq(endpointDelegate(address(aToken)), OWNER);
  }

  function test_constructor_setsEndpoint() public view {
    assertEq(address(aToken.endpoint()), endpoints[A_EID]);
    assertEq(address(bToken.endpoint()), endpoints[B_EID]);
  }

  function test_constructor_isNativeOft() public view {
    assertEq(aToken.token(), address(aToken));
    assertFalse(aToken.approvalRequired());
  }

  function test_constructor_sharedDecimalsIsSix() public view {
    assertEq(aToken.sharedDecimals(), 6);
    assertEq(aToken.decimalConversionRate(), 1e12);
  }

  function test_constructor_hasNoMintFunction() public {
    (bool ok,) = address(aToken).call(abi.encodeWithSignature('mint(address,uint256)', ALICE, 1));
    assertFalse(ok);
  }

  function test_constructor_revertsWhen_delegateIsZero() public {
    vm.expectRevert();
    new QuipToken(NAME, SYMBOL, endpoints[A_EID], address(0), TREASURY);
  }

  function test_constructor_revertsWhen_endpointHasNoCode() public {
    vm.expectRevert();
    new QuipToken(NAME, SYMBOL, makeAddr('noEndpoint'), OWNER, TREASURY);
  }

  function endpointDelegate(address oapp) internal view returns (address) {
    (bool ok, bytes memory ret) = endpoints[A_EID].staticcall(abi.encodeWithSignature('delegates(address)', oapp));
    require(ok, 'delegates() failed');
    return abi.decode(ret, (address));
  }
}
