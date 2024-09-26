# pls-lsd-ejector

Ejector service plays an important role in PLS LSD stack. Every validator should run an ejector service to properly handle the validator exiting process, as users are free to `unstake` and `withdraw` vPLS as they need, it is important for valditors to exit gracefully when required.

To learn more about PLS LSD, see [**PLS LSD Documentation and Guide**](https://vouch.run/docs/architecture/vouch_lsd.html)

## Running With Docker

To get started running an ejector node, you can use our pre-built Docker images.

```bash
docker run -v /path/to/keys:/keys gcr.io/<path>:latest start --keys_dir /keys --withdraw_address <address> --consensus_endpoint <endpoint> --execution_endpoint <endpoint>
```