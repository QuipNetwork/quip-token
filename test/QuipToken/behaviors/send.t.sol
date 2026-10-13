// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {QuipTokenTest} from '../QuipToken.t.sol';
import {IOFT, MessagingFee, OFTReceipt, SendParam} from '@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol';
import {IERC20Errors} from '@openzeppelin/contracts/interfaces/draft-IERC6093.sol';

contract QuipToken_send is QuipTokenTest {
  function test_send_burnsOnSourceAndMintsOnDestination() public {
    uint256 amount = 100 ether;
    _bridge(aToken, B_EID, address(bToken), ALICE, BOB, amount);

    assertEq(aToken.balanceOf(ALICE), ALICE_BALANCE - amount);
    assertEq(aToken.totalSupply(), aToken.TOTAL_SUPPLY() - amount);
    assertEq(bToken.balanceOf(BOB), amount);
    assertEq(bToken.totalSupply(), amount);
  }

  function test_send_roundTripRestoresHomeSupply() public {
    uint256 amount = 100 ether;
    _bridge(aToken, B_EID, address(bToken), ALICE, BOB, amount);
    _bridge(bToken, A_EID, address(aToken), BOB, ALICE, amount);

    assertEq(aToken.balanceOf(ALICE), ALICE_BALANCE);
    assertEq(aToken.totalSupply(), aToken.TOTAL_SUPPLY());
    assertEq(bToken.totalSupply(), 0);
  }

  function test_send_conservesGlobalSupply() public {
    _bridge(aToken, B_EID, address(bToken), ALICE, BOB, 250 ether);
    _bridge(bToken, A_EID, address(aToken), BOB, ALICE, 50 ether);
    assertEq(aToken.totalSupply() + bToken.totalSupply(), aToken.TOTAL_SUPPLY());
  }

  function test_send_leavesDustWithSender() public {
    uint256 dust = 123_456_789; // below 1e12, the shared-decimals conversion rate
    uint256 amount = 1 ether + dust;
    OFTReceipt memory receipt = _bridge(aToken, B_EID, address(bToken), ALICE, BOB, amount);

    assertEq(receipt.amountSentLD, 1 ether);
    assertEq(receipt.amountReceivedLD, 1 ether);
    assertEq(aToken.balanceOf(ALICE), ALICE_BALANCE - 1 ether);
    assertEq(bToken.balanceOf(BOB), 1 ether);
  }

  function test_send_quoteOftReportsNoFee() public view {
    (,, OFTReceipt memory receipt) = aToken.quoteOFT(_sendParam(B_EID, BOB, 5 ether));
    assertEq(receipt.amountSentLD, 5 ether);
    assertEq(receipt.amountReceivedLD, 5 ether);
  }

  function test_send_emitsOftSent() public {
    SendParam memory param = _sendParam(B_EID, BOB, 1 ether);
    MessagingFee memory fee = aToken.quoteSend(param, false);

    vm.expectEmit(false, true, true, true, address(aToken));
    emit IOFT.OFTSent(bytes32(0), B_EID, ALICE, 1 ether, 1 ether);
    vm.prank(ALICE);
    aToken.send{value: fee.nativeFee}(param, fee, payable(ALICE));
  }

  function test_send_revertsWhen_slippageExceeded() public {
    MessagingFee memory fee = aToken.quoteSend(_sendParam(B_EID, BOB, 1 ether), false);
    // Dust is truncated, so 1 ether + 1 sends 1 ether — short of its own minimum.
    SendParam memory param = _sendParam(B_EID, BOB, 1 ether + 1);

    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(IOFT.SlippageExceeded.selector, 1 ether, 1 ether + 1));
    aToken.send{value: fee.nativeFee}(param, fee, payable(ALICE));
  }

  function test_send_revertsWhen_balanceInsufficient() public {
    uint256 amount = ALICE_BALANCE + 1 ether;
    SendParam memory param = _sendParam(B_EID, BOB, amount);
    MessagingFee memory fee = aToken.quoteSend(param, false);

    vm.prank(ALICE);
    vm.expectRevert(
      abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, ALICE_BALANCE, amount)
    );
    aToken.send{value: fee.nativeFee}(param, fee, payable(ALICE));
  }

  function test_send_revertsWhen_peerNotSet() public {
    SendParam memory param = _sendParam(99, BOB, 1 ether);

    vm.prank(ALICE);
    vm.expectRevert();
    aToken.send{value: 1 ether}(param, MessagingFee(1 ether, 0), payable(ALICE));
  }
}
