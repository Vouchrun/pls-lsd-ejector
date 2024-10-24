# pls-lsd-ejector

Ejector service plays an important role in PLS LSD stack. Every validator should run an ejector service to properly handle the validator exiting process, as users are free to `unstake` and `withdraw` vPLS as they need, it is important for valditors to exit gracefully when required.

To learn more about PLS LSD, see [**PLS LSD Documentation and Guide**](https://vouch.run/docs/architecture/vouch_lsd.html)

## Quick Install

The below command will:
- Install Docker (if not already installed)
- Configure ejector directory and keystore
- Enable automatic OS and ejector updates (optional)
- Start the Relay docker container


Note: this command needs to be run as root.

```bash
curl -sL https://raw.githubusercontent.com/Vouchrun/pls-lsd-ejector/refs/heads/main/ejector-install.sh > ejector-install.sh; bash ejector-install.sh
```