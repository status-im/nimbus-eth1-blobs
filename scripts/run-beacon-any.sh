#! /bin/sh
#
# Example running four sessions simultaneously.
#
# Usage:
#
#   start as "sh run-beacon-any.sh start"
#
#   stop as "sh run-beacon-any.sh stop"
#
#   or clean up as "sh run-beacon-any.sh stop flush"
#

export BEACON_SESSION_SELF=`basename "$0"`

for instance in 0 1 2 3
do (
      export BEACON_SESSION_INSTANCE=$instance
      sh ../nimbus-eth1-blobs/scripts/run-beacon-session.sh "$@"
      sleep 1
   )
done

# End
