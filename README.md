# Aptos CoinV2 Playground

Experiment with the brand new Fungible Asset standard by Aptos. Including:

- [Coin V2](./sources/coin_v2.move): An `0x1::coin` implementation using `0x1::fungible_asset`.
- [CToken](./sources/ctoken.move): A Compound CToken implementation that allows admin coin transfer between 2 user accounts, which is required in liquidation.
