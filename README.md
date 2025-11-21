# pls-lsd-ejector

Ejector service plays an important role in PLS LSD stack. Every validator should run an ejector service to properly handle the validator exiting process, as users are free to `unstake` and `withdraw` vPLS as they need, it is important for valditors to exit gracefully when required.

To learn more about PLS LSD, see [**PLS LSD Documentation and Guide**](https://vouch.run/docs/architecture/vouch_lsd.html)

## Quick Install

The below command will:

- Download the ejector management tool ejector-menu.sh which:
  - Installs Docker (if not already installed)
  - Creates a "ejector" user and "docker" group
  - Selects mode of operation i.e. Detached or Interactive
  - Configures ejector settings (and saves to a file)
  - Controls; starting, stopping and removal of ejector client
    - runs the docker container using the ejector user and docker group.


**Notes: this command needs to be run as root.**

```bash
curl -sL https://raw.githubusercontent.com/Vouchrun/pls-lsd-ejector/refs/heads/staging/ejector-menu.sh > ejector-menu.sh; sudo chmod +x ejector-menu.sh && sudo ./ejector-menu.sh
```


For detailed instructions read the [Ejector Client Documentation](https://vouch.run/docs/validator_guide/ejector_client.html)