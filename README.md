# eth-lsd-ejector

Ejector service plays an important role in ETH LSD stack. Every validator should run an ejector service to properly handle the validator exiting process, as users are free to `unstake` and `withdraw`.

To learn more about ETH LSD stack, see [**ETH LSD Stack Documentation and Guide**](https://github.com/stafiprotocol/stack-docs/blob/main/README.md#eth-lsd-stack)

### Start service

Note: keys_dir is a directory where the keystore created by [`deposit-cli`](https://github.com/ethereum/staking-deposit-cli).

```bash
$ eth-lsd-ejector start \
    --consensus_endpoint 'YOUR_BEACON_CHAIN_RPC_ENDPOINT' \
    --execution_endpoint 'YOUR_EXECUTION_RPC_ENDPOINT'  \
    --keys_dir ./validator_keys \
    --withdraw_address 0xYOUR_WITHDRAWAL_ADDRESS
```
