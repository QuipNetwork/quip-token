# QuipToken

The Quip network token: a LayerZero V2 OFT modelled one-for-one on the LayerZero
ZRO token ([`LayerZeroToken`](https://etherscan.io/token/0x6985884C4392D348587B19cb9eAAf157F13271cd#code)).

- OpenZeppelin `ERC20` + LayerZero `OFT` + `Ownable`. Nothing else: no proxy, no
  `mint`, no pause, no fees, no blocklist.
- 1,000,000,000 QUIP (18 decimals), minted once in the constructor on the home
  chain. Remote chains start at zero; OFT `_credit` only re-mints what `_debit`
  burned elsewhere.
- Shared decimals 6 (OFT default).
- Owner and LayerZero delegate initially share an address. The owner can
  replace the delegate; renouncing ownership also revokes the current endpoint
  delegate, so neither retains configuration authority.

## Difference from ZRO

ZRO ships two sources at one address (home: constructor mints to a hardcoded
treasury; remotes: empty constructor). QuipToken is one contract whose
`initialHolder_` argument receives the supply on the home chain and is
`address(0)` everywhere else. The deploy scripts derive it from
`script/DeployConstants.sol`, never from env.

## Deployment

Same scheme as `quip-swap-solidity` and `quip-solidity`: the canonical CreateX
factory (`0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed`), CREATE3, permissioned salt

```
rawSalt     = DEPLOYER ‖ 0x00 ‖ bytes11(keccak256(label))
guardedSalt = keccak256(bytes32(DEPLOYER) ‖ rawSalt)
address     = CREATE3(CreateX, guardedSalt)
```

so the token has **one address on every chain, mainnet and testnet**:
`0xc24c621b479326a40e21cA7D104ebAB65826a662` (label `QUIP:QuipToken:v1.0.0`),
regardless of constructor args, and only the ops EOA can claim it.

| Family | Home chain (mints) | Chains |
|---|---|---|
| Mainnet | Ethereum | Ethereum, Base |
| Testnet | Sepolia | Sepolia, Base Sepolia |

`forge script script/PredictAddresses.s.sol` re-derives it offline. Freeze the
label before mainnet: bumping it moves the address on every chain.

Order per family: home chain first (mints), then remotes, then wire peers from
the delegate. `MAINNET_INITIAL_HOLDER` is deliberately unset; the mainnet home
deploy aborts until it is set to the treasury multisig.

```sh
make install
make test
make test-fork                                   # needs API_URL_BASE_SEPOLIA
make deploy-dry RPC=API_URL_SEPOLIA              # every gate, no broadcast
make deploy-dry-wrong-signer RPC=API_URL_SEPOLIA # must report OK (rejected)
make deploy-sepolia && make deploy-base-sepolia
make wire RPC=API_URL_SEPOLIA                    # print plan per chain
make wire RPC=API_URL_BASE_SEPOLIA
```

## Wiring

`script/WireQuipToken.s.sol` connects the token on the current chain to every
other chain in its family, using `script/LzConfig.sol` (addresses from
LayerZero's official metadata):

- peer = the same token address on the remote chain
- ULN302 send/receive libraries pinned (not following LayerZero defaults)
- 2-of-2 required DVNs (LayerZero Labs + Nethermind), explicitly stored for
  this token even when the current defaults match; default optional DVNs off
- executor with a 10 kB message cap
- block confirmations: Ethereum 15, Base 10, testnets 2 (source chain's value on both ends)
- enforced 80k `lzReceive` gas for `SEND` and `SEND_AND_CALL`

Security overrides are written before selecting their libraries, and the peer
is enabled only after receive security is configured. Preserve the printed call
order when executing a multisig plan. Later changes to LayerZero defaults cannot
change the pinned DVNs, confirmations, or executor.

It only emits calls that differ from the effective and app-specific state, so a
fully wired chain plans zero calls. Without `DELEGATE_PK` it prints target + calldata for the
multisig; with it, it broadcasts and re-checks.

## Reproduce audit J

Run the exact reviewed code at `e895a5974166d09018c8ded04d4e9ea8cdf979a1`:

```sh
python3 scripts/reproduce-audit-j.py
```

Requirements are Python 3, Git, curl, tar, and network access. The script supports
macOS and Linux on ARM64 and x86-64. It downloads official [Foundry 1.9.0](https://github.com/foundry-rs/foundry/releases/tag/v1.9.0)
(commit `6056c5845d34205a83cf7108042adb137325c9df`) and
[Bun 1.4.4](https://github.com/oven-sh/bun/releases/tag/bun-v1.4.4), checks the
platform-specific archive SHA-256 pins, and installs them under
`.audit-tools/foundry-1.9.0-bun-1.4.4-<platform>/bin`. It does not use Foundry or
Bun from your PATH. Forge obtains the `0.8.33` compiler pinned in `foundry.toml`.

Each run exports the reviewed Git revision into a fresh `.audit-tools/audit-j-*/source`
directory, installs the frozen Bun dependencies and pinned Soldeer dependencies,
and captures commands, versions, environment details and test output in the
adjacent `logs` directory. Soldeer's added lock-format marker is removed only
if all pinned entries remain byte-identical; all exported source files must
remain unchanged. The runner requires all **81 tests to pass with no skips**, including
the four real fork suites (31 tests), against Base Sepolia block **48,000,000**.
It uses one test thread and disables persistent RPC storage caching, so an old
personal fork cache cannot satisfy the run.

The default RPC is `https://sepolia.base.org`. This is a public, rate-limited,
best-effort endpoint, as documented by [Base](https://docs.base.org/get-started/connect-to-base).
For throttling or archive-state availability failures, supply a Base Sepolia
archive RPC explicitly and rerun; there is no silent endpoint fallback:

```sh
API_URL_BASE_SEPOLIA=https://your-base-sepolia-archive-rpc python3 scripts/reproduce-audit-j.py
```

No deployment keys are needed. This runner calls `forge test`, never a broadcast
or deployment script. A failed download, RPC request, test, missing fork suite or
skipped test fails the reproduction; it is not reported as an offline pass.
