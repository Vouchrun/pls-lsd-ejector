# pls-lsd-ejector

Ejector service plays an important role in PLS LSD stack. Every validator should run an ejector service to properly handle the validator exiting process, as users are free to `unstake` and `withdraw` vPLS as they need, it is important for valditors to exit gracefully when required.

To learn more about PLS LSD, see [**PLS LSD Documentation and Guide**](https://vouch.run/docs/architecture/vouch_lsd.html)