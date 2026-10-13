# QuipToken

The Quip network token: a LayerZero V2 OFT modelled one-for-one on the LayerZero
ZRO token ([`LayerZeroToken`](https://etherscan.io/token/0x6985884C4392D348587B19cb9eAAf157F13271cd#code)).

- OpenZeppelin `ERC20` + LayerZero `OFT` + `Ownable`. Nothing else: no proxy, no
  `mint`, no pause, no fees, no blocklist.
- 1,000,000,000 QUIP (18 decimals), minted once in the constructor on the home
  chain. Remote chains start at zero; OFT `_credit` only re-mints what `_debit`
  burned elsewhere.
- Shared decimals 6 (OFT default).
- Owner = LayerZero delegate: configures peers, enforced options and DVNs only.

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
- 2-of-2 required DVNs (LayerZero Labs + Nethermind), default optional DVNs off
- executor with a 10 kB message cap
- block confirmations: Ethereum 15, Base 10, testnets 2 (source chain's value on both ends)
- enforced 80k `lzReceive` gas for `SEND` and `SEND_AND_CALL`

It only emits calls that differ from on-chain state, so a fully wired chain
plans zero calls. Without `DELEGATE_PK` it prints target + calldata for the
multisig; with it, it broadcasts and re-checks.
