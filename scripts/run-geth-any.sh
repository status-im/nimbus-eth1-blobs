#! /bin/sh

export GETH_SESSION_SELF=`basename "$0"`
export GETH_SESSION_NAME=kiln
export GETH_SESSION_BASE_PORT=30800
export GETH_SERVER_API=yes

for instance in 0 1 2 3
do (
      export GETH_SESSION_INSTANCE=$instance
      sh ../nimbus-eth1-blobs/scripts/run-geth-session.sh "$@"
      sleep 1
   )
done

# End
