# Nimbus Blobs - Debugging data & Scripts

This module contains helpers for test driven development as
- source code examples of how to produce and replay data dumps
- miscellaneous helper scripts, typically for setting up temporary nodes

## Caveat

This module is neither part of the *Nimbus* code, nor part of the automated
continuous integration tests. It must not be assumed present by default.

So there must be *no reference* from the active *Nimbus* code or *CI* procedures
into this module. Any code found here that might be handy in the *Nimbus*
distribution must be copied.
