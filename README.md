<h3 align="center">Rari Vault Strategies</h3>

<div align="center">

[![Tests](https://github.com/Rari-Capital/vaults/actions/workflows/tests.yml/badge.svg)](https://github.com/Rari-Capital/vaults/actions/workflows/tests.yml) [![License](https://img.shields.io/badge/License-AGPL--3.0-blue)](LICENSE.md)

</div>

<p align="center">Simple (potentially composable) Strategies for earning yield on Rari Vaults.</p>

### Credits

-   [t11s](https://twitter.com/transmissions11), [Jet Jadeja](https://twitter.com/JetJadeja), and the whole [Rari Capital](https://twitter.com/raricapital) team for their exceptional work.
-   [Georgios Konstantopoulos](https://github.com/gakonst) for the amazing [dapptools-template](https://github.com/gakonst/dapptools-template) resource.

## Architecture

- [`IdleStrategy.sol`](src/IdleStrategy.sol): An Idle Strategy which generates no yield for a user's deposit.
- [`interfaces/`](src/interfaces): Interfaces of external contracts Vaults and modules interact with.
  - [`Strategy.sol`](src/interfaces/Strategy.sol): Minimal interfaces for ERC20 and ETH compatible strategies.

## Contributing

Install [DappTools](https://dapp.tools) with the official [installation guide](https://github.com/dapphub/dapptools#installation).

### Setup

```sh
git clone https://github.com/abigger87/vault-strategies.git
cd vault-strategies
make
```

### Run Tests

```sh
dapp test
```

### Measure Coverage

```sh
dapp test --coverage
```

### Update Gas Snapshots

```sh
dapp snapshot
```

### Kovan

Rari Capital [VaultFactory](https://kovan.etherscan.io/address/0xc99a698dfB1eB38E0649e6d2d3462Bc2476dE0B4) at `0xc99a698dfB1eB38E0649e6d2d3462Bc2476dE0B4`

Underlying Token [RAI](https://kovan.etherscan.io/token/0x76b06a2f6df6f0514e7bec52a9afb3f603b477cd) at `0x76b06a2f6df6f0514e7bec52a9afb3f603b477cd`

Deployed [Vault](https://kovan.etherscan.io/address/0x58a4cc1f3c268af914c7f23fb1c7510c3033cbca) ad `0x58a4cc1f3c268af914c7f23fb1c7510c3033cbca`

Using our previously deployed vault as the underlying, deployed
[Vault](https://kovan.etherscan.io/address/0xf4e6b1e4f4605c9a43bfa67ba30045ff2a6966a8) at `0xf4e6b1e4f4605c9a43bfa67ba30045ff2a6966a8`

Deployed Strategy to Kovan running:

```sh
ETH_FROM=xxxx ETH_RPC_URL=xxxx ETH_GAS=xxxx dapp create src/IdleStrategy.sol:IdleStrategy <ETH_FROM> 0x76b06a2f6df6f0514e7bec52a9afb3f603b477cd --verify
```

Then verified with:

```
ETH_FROM=xxxx ETH_RPC_URL=xxxx ETH_GAS=xxxx dapp verify-contract ./src/IdleStrategy.sol:IdleStrategy <Deployed IdleStrategy Address> <ETH_FROM> 0x76b06a2f6df6f0514e7bec52a9afb3f603b477cd
```


### Generate Pretty Visuals

We use [surya](https://github.com/ConsenSys/surya) to create contract diagrams.

Run `yarn visualize` to generate an amalgamated contract visualization in the `./assets/` directory. Or use the below commands for each respective contract.
