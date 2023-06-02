# Aptos Playground

Experiment with WIP Aptos features. Including:

## Fungible Asset

- [Coin V2](./sources/coin_v2.move): An `0x1::coin` implementation using `0x1::fungible_asset`.
- [CToken](./sources/ctoken.move): A Compound CToken implementation that allows admin coin transfer between 2 user accounts, which is required in liquidation.

## Object

- [Vault](./sources/vault.move): A vault implementation that allows users to deposit assets into different markets.
