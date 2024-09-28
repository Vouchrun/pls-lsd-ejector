# pls-lsd-ejector

Ejector service plays an important role in PLS LSD stack. Every validator should run an ejector service to properly handle the validator exiting process, as users are free to `unstake` and `withdraw` vPLS as they need, it is important for valditors to exit gracefully when required.

To learn more about PLS LSD, see [**PLS LSD Documentation and Guide**](https://vouch.run/docs/architecture/vouch_lsd.html)

## Running With Docker

To get started running an ejector node, you can use our pre-built Docker images.

You'll need to set the KEYSTORE_PASSWORD environment variable to run this command, you can either do this through your method of deploying (eg: Kubernetes, Kamal Deploy, Swarm). Or by running the command with `KEYSTORE_PASSWORD="password"` prefixed, if you do this, make sure to add a leading ` ` (space) before the command to prevent it from being saved to your bash history!

```bash
docker run --name ejector-client -d --restart always -e KEYSTORE_PASSWORD -v /path/to/your/keystore:/keys ghcr.io/Vouchrun/pls-lsd-ejector:main start \
    --consensus_endpoint  <RPC_ENDPOINT> \
    --execution_endpoint <RPC_ENDPOINT> \
    --keys_dir  /keys \
    --withdraw_address <WITHDRAW_ADDRESS>
```