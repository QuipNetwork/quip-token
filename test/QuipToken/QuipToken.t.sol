// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.33;

import {QuipToken} from '../../src/QuipToken.sol';
import {OptionsBuilder} from '@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol';
import {MessagingFee, OFTReceipt, SendParam} from '@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol';
import {TestHelperOz5} from '@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol';

/// @title QuipToken Base Test
/// @dev Two mock LayerZero endpoints: A is the home chain (mints the supply),
///      B is a remote chain (starts at zero). Both tokens are wired as peers.
contract QuipTokenTest is TestHelperOz5 {
  using OptionsBuilder for bytes;

  uint32 internal constant A_EID = 1;
  uint32 internal constant B_EID = 2;

  string internal constant NAME = 'Quip';
  string internal constant SYMBOL = 'QUIP';

  QuipToken public aToken;
  QuipToken public bToken;

  address public OWNER = makeAddr('owner');
  address public TREASURY = makeAddr('treasury');
  address public ALICE = makeAddr('alice');
  address public BOB = makeAddr('bob');

  uint256 public constant ALICE_BALANCE = 1000 ether;

  function setUp() public virtual override {
    super.setUp();
    setUpEndpoints(2, LibraryType.UltraLightNode);

    aToken = _deployQuipToken(endpoints[A_EID], TREASURY);
    bToken = _deployQuipToken(endpoints[B_EID], address(0));

    vm.prank(OWNER);
    aToken.setPeer(B_EID, addressToBytes32(address(bToken)));
    vm.prank(OWNER);
    bToken.setPeer(A_EID, addressToBytes32(address(aToken)));

    vm.prank(TREASURY);
    aToken.transfer(ALICE, ALICE_BALANCE);
    vm.deal(ALICE, 10 ether);
  }

  function test_setUp() public view virtual {
    assertEq(aToken.totalSupply(), aToken.TOTAL_SUPPLY());
    assertEq(aToken.balanceOf(TREASURY), aToken.TOTAL_SUPPLY() - ALICE_BALANCE);
    assertEq(aToken.balanceOf(ALICE), ALICE_BALANCE);
    assertEq(bToken.totalSupply(), 0);
    assertEq(aToken.peers(B_EID), addressToBytes32(address(bToken)));
    assertEq(bToken.peers(A_EID), addressToBytes32(address(aToken)));
  }

  function _deployQuipToken(address endpoint_, address initialHolder_) internal returns (QuipToken) {
    return new QuipToken(NAME, SYMBOL, endpoint_, OWNER, initialHolder_);
  }

  function _sendParam(uint32 dstEid, address to, uint256 amount) internal pure returns (SendParam memory) {
    bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
    return SendParam(dstEid, bytes32(uint256(uint160(to))), amount, amount, options, '', '');
  }

  /// @dev Sends `amount` from `from` on `src` to `to` on the peer chain and
  ///      delivers the packet.
  function _bridge(
    QuipToken src,
    uint32 dstEid,
    address dst,
    address from,
    address to,
    uint256 amount
  ) internal returns (OFTReceipt memory receipt) {
    SendParam memory param = _sendParam(dstEid, to, amount);
    param.minAmountLD = 0;
    MessagingFee memory fee = src.quoteSend(param, false);
    vm.deal(from, from.balance + fee.nativeFee);
    vm.prank(from);
    (, receipt) = src.send{value: fee.nativeFee}(param, fee, payable(from));
    verifyPackets(dstEid, addressToBytes32(dst));
  }
}
