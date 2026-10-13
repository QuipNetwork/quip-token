# CLAUDE.md

## Solidity Testing Patterns (Foundry)

This project uses Foundry for Solidity testing. All tests are written in Solidity using forge-std.

### Principles

- Every public/external function has a dedicated test file in `behaviors/`
- Every code path tested: success cases, all reverts (`revertsWhen_`), edge cases (zero/max/empty/boundary)
- One behavior per test function; tests must not depend on each other
- Test: state changes, return values, events, access control, pausability, input validation

### Directory Structure

All test files use `.t.sol` extension. Harnesses use `.sol`.

```
test/
├── {ContractName}/
│   ├── {ContractName}.t.sol        # Base test (setUp, helpers, test_setUp)
│   ├── behaviors/
│   │   ├── {fn}.t.sol              # Public function tests
│   │   └── _{fn}.t.sol             # Internal function tests
│   ├── integration/                 # Fork tests
│   ├── scenario/                    # Simulation tests
│   └── invariant/
│       ├── InvariantBase.sol       # Shared invariant checks
│       ├── Handler.t.sol           # Fuzz handler
│       └── {Context}.t.sol         # e.g., Local.t.sol, BSC.t.sol
└── harness/
    └── {ContractName}Harness.sol   # Exposes internals via exposed_{fn}()
```

### Naming

**Contracts:** `{Contract}Test` (base), `{Contract}_{fn}` (behavior), `{Contract}__{fn}` (internal), `{Contract}Harness`

**Test functions:**
```
test_{fn}_{behavior}()
test_{fn}_revertsWhen_{condition}()
test_exposed_{fn}_{behavior}()
test_simulation_{scenario}()
test_setUp()
invariant_{description}()
```

**Helpers (internal):** `_stakeFor()`, `_timeskip()`, `_deploy{Contract}()`, `_assertEq{Type}()`, `_assertInvariant_{desc}()`

### Base Test Structure

```solidity
/// @title {ContractName} Base Test
/// @dev Base contract for testing {ContractName}
contract {ContractName}Test is Test {
    struct Actor { address account; bytes32[] proof; }

    {ContractName}Harness public pool;
    ERC20Mock public mockToken;

    address public ADMIN = makeAddr("admin");
    address public ALICE = makeAddr("alice");
    uint256 public constant STAKE_AMOUNT = 10 ether;

    Actor alice = Actor({ account: ALICE, proof: aliceProof });

    function setUp() public virtual { /* deploy, configure, mint */ }
    function test_setUp() public view virtual { /* assert setup */ }
    function _stakeFor(Actor memory actor, uint256 amount) internal { ... }
}
```

### setUp Inheritance

| Type | Pattern |
|------|---------|
| Behavior | Inherit as-is |
| Scenario | `super.setUp()` + config overrides |
| Integration | Full override with `vm.createSelectFork()` |
| Invariant | Own setUp + `handler` + `targetContract()` |

### Test Patterns

```solidity
// State change: before/after delta
uint256 before = token.balanceOf(addr);
_action();
assertEq(before - token.balanceOf(addr), expected);

// Revert
vm.expectRevert(Error.selector);
// or: vm.expectRevert(abi.encodeWithSelector(Error.selector, param));
contract.fn();

// Access control
vm.prank(NON_ADMIN);
vm.expectRevert(abi.encodeWithSelector(
    IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ROLE));
pool.adminFn();

// Events
vm.recordLogs();
contract.fn();
Vm.Log[] memory logs = vm.getRecordedLogs();
assertEq(logs[0].topics[0], Event.selector);
```

### Cheatcodes

| Code | Use |
|------|-----|
| `vm.prank(a)` / `vm.startPrank(a)` | Impersonate |
| `vm.expectRevert(sel)` | Assert revert |
| `vm.warp(t)` / `vm.roll(n)` | Set time/block |
| `deal(tok, a, amt)` | Set balance |
| `vm.recordLogs()` | Capture events |
| `vm.createSelectFork(rpc, blk)` | Fork |
| `bound(v, min, max)` | Bound fuzz input |
