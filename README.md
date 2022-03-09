# Nimbus Blobs - Debugging data & Scripts

This module contains helpers for test driven development as
- blockchain data dumps for replay
- source code examples of how to roduce and replat data dumps
- miscellaneous helper scripts, typically for setting up temporary nodes

# Usage

Typically, this module is intended to live paralell to the *nimbus-eth1* file
system under the name *nimbus-eth1-blobs*. This makes a reliable rule for
TDD scripts and tests.

## Caveat

This module is neither part of the *Nimbus* code, not part of the automated
continuous integration tests. It is not available by default module update.

So there must be *no reference* from the active *Nimbus* code or *CI* procedures
into this module. Any code found here that might be handy in the *Nimbus*
distribution must be copied.
