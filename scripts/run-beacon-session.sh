#! /bin/sh

self=${BEACON_SESSION_SELF:-`basename "$0"`}

# Network name (used below for easy setup)
name=${BEACON_SESSION_NAME:-kiln}
fullname=${BEACON_SESSION_FULLNAME:-$name}

# Digits, instance id appended to directory name
instance=${BEACON_SESSION_INSTANCE:-0}

# Unique beacon TCP/UDP communication port => tcp_port + instance
base_tcpport=${BEACON_SESSION_TCP_PORT:-9000}
base_udpport=${BEACON_SESSION_UDP_PORT:-9000}

# Unique execution layer communication port => base_port + instance * 10
base_rpcport=${BEACON_SESSION_RPC_PORT:-8551}

# Beacon sync mode, full, snap, or light
syncmode=${BEACON_SESSION_SYNCMODE:-full}

# Git branch to use with "build" command
git_branch=${BEACON_GIT_BRANCH:-kiln-dev-auth}

# Unique log data and database folder (relative to current directory)
datadir=${BEACON_SESSION_DATADIR:-./datadir-beacon-$name$instance}

# Terminal total difficulty
ttd=${BEACON_SERVER_TTD:-20000000000000}

# Adding generic options
optargs=${BEACON_SESSION_OPTARGS:-'--nat=none'}

# ------------------------------------------------------------------------------
# No need to change, below
# ------------------------------------------------------------------------------

# TCP/UDP communication ports
tcp_port=`expr $base_tcpport + $instance`
udp_port=`expr $base_udpport + $instance`
rpc_port=`expr $base_rpcport + $instance \* 10`

# Log spooler capacity settings
logfile_max=80000000
num_backlogs=40

# Base directory for finding objects in the Beacon file system
find_prefix="`dirname $0` . .. ../.."
find_prefix="$find_prefix ../nimbus-eth1"
find_prefix="$find_prefix    go-ethereum ../nethermind    nimbus-eth1-blobs"
find_prefix="$find_prefix ../go-ethereum ../nethermind ../nimbus-eth1-blobs"

# Sub-find directory for various items
find_beacon=". .. build/bin"
find_yamlconf="merge-testnets/$fullname $fullname"
find_jwtsecret=
find_jwtsecret="$find_jwtsecret datadir-geth-$name$instance"
find_jwtsecret="$find_jwtsecret datadir-nimbus-$name"
find_jwtsecret="$find_jwtsecret datadir-$name$instance"

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

# Find executable file
find_exe() { # Syntax: <exe-name> <subdir> ...
    exe="$1"
    shift
    {
	for pfx in $find_prefix; do
	    for sub; do
		find -L \
		     "$pfx/$sub" \
		     -maxdepth 3 -type f -name "$exe" -perm /111 -print \
		     2>/dev/null
	    done
	done |
	    # Beware, this is slow. On the other hand, uncommenting the
	    # next line dumps all possible matches to the console.
	    #tee /dev/tty |
	    xargs -n1 realpath 2>/dev/null
	# provide argument file name as default
	echo "$exe"
    } |	sed -eq
}

# Find non-executable file
find_file() { # Syntax: <file-name> <subdir> ...
    file="$1"
    shift
    {
	for pfx in $find_prefix; do
	    for sub; do
		find -L \
		     "$pfx/$sub" \
		     -maxdepth 3 -type f -name "$file" -print \
		     2>/dev/null
	    done |
		# Beware, this is slow. On the other hand, uncommenting the
		# next line dumps all possible matches to the console.
		#tee /dev/tty |
		xargs -n1 realpath 2>/dev/null
	done
	# provide argument file name as default
	echo "$file"
    } | sed -eq
}

stripColors() {
  if ansi2txt </dev/null 2>/dev/null
  then
      ansi2txt
  else
      cat
  fi
}

# Find pid of running svlogd command
get_pid_svlogd() {
    ps x|
	grep \
	    -e "svlogd $datadir/log" \
        |
	grep -v \
	     -e vim \
	     -e grep \
        |
	awk '$1 != '"$$"'{print $1}'
}

# Find pid of running svlogd and beacon command
get_pids() {
    cmd=nimbus_beacon_node
    cmd="$cmd --data-dir=./data"
    cmd="$cmd --web3-url=ws://127.0.0.1:$rpc_port"
    cmd="$cmd --tcp-port=$tcp_port"
    ps x|
	grep \
	    -e "$cmd" \
	    -e "svlogd $datadir/log" \
        |
	grep -v \
	     -e vim \
	     -e grep \
        |
	awk '$1 != '"$$"'{print $1}'
}

# ------------------------------------------------------------------------------
# Command line parsing and man page
# ------------------------------------------------------------------------------

nohup=no
start=no
stop=no
flush=no
logs=no
help=no
build=no
enode=no
attch=no

test $# -ne 0 ||
    help=yes

for arg
do
    case "$arg" in
    build)
	build=yes
	;;
    enode)
	enode=yes
	;;
    attach)
	attch=yes
	;;
    stop)
	stop=yes
	;;
    flush)
	flush=yes
	;;
    start)
	start=yes
	;;
    daemon)
	nohup=yes
	start=yes
	;;
    logs)
	logs=yes
	;;
    help|'')
	help=yes
	;;
  *)
      exec >&2
      echo "Usage: $self [help] [stop] [flush] [daemon|start|enode|attach] [logs]"
      exit 2
  esac
done


test yes != "$help" || {
    cat <<EOF
$self:
   Available commands (can be combined irrespective of order):
      logs    resume console logging
      flush   delete all log and blockchain data
      build   re-compile geth version

   Mutually exclusive commands:
      stop    stop the Geth session (as descibed above)
      start   start the Geth session in the foreground
      daemon  background session (without termninating on logout, e.g. from ssh)
EOF
    exit
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# Check for logger program availability
(svlogd 2>&1|grep -i 'usage: svlogd' >/dev/null) || {
    exec >&2
    echo "*** $self: This script needs a working \"svlogd\" program. On Debian,"
    echo "                    this is provided by the \"runit\" package."
    exit 2
}

# Stop running sessions by sending termination signal
test yes != "$stop" || {
    # set -x
    pids=`get_pids`
    test -z "$pids" || {
	(set -x; kill -TERM $pids)
	sleep 1
	pids=`get_pids`
	test -z "$pids" || {
	    (set -x; kill -KILL $pids)
	    sleep 1
	}
	echo
    }
}

# Clean up
test yes != "$flush" || {
    d=`basename $datadir`
    test \! -d $datadir || (set -x; rm -rf $datadir)
}

# Stop here after clean up when terminating a session
test yes != "$stop" || {
    exit
}

if [ yes = "$nohup" ]
then
    true
elif [ yes != "$flush" -a yes != "$build" ]
then
    # Set logging unless deamon enabled or build
    logs=yes
fi

# Rebuild Getn version
test yes != "$build" || (
    set -x
    git checkout "$git_branch"
    git pull origin "$git_branch"
    make update OVERRIDE=1
    make nimbus_beacon_node
) || exit


# Start a new geth session in the background
test yes != "$start" || (
  mkdir -p $datadir/log $datadir/data

  beacon=`find_exe nimbus_beacon_node $find_beacon`
  jwtsecret=`find_file jwtsecret $find_jwtsecret`
  yamlconf=`find_file config.yaml $find_yamlconf`
  confdir=`dirname "$yamlconf"`

  test yes != "$nohup" || {
     trap "echo '*** $self: NOHUP ignored'" HUP
     trap "echo '*** $self: terminating ..';exit"  INT TERM QUIT
  }
  (
    cd $datadir

    mv ./log/config ./log/config~ 2>/dev/null || true
    {
       echo s$logfile_max
       echo n$num_backlogs
    } >./log/config

    set -x
    ${beacon:-nimbus_beacon_node} \
	--data-dir=./data \
	--web3-url=ws://127.0.0.1:$rpc_port \
	--tcp-port=$tcp_port \
	--udp-port=$udp_port \
	--network=$confdir \
	--jwt-secret=$jwtsecret \
	--terminal-total-difficulty-override=$ttd \
	--rest \
	--metrics \
	$optargs \
	--log-level=DEBUG \
	--non-interactive \
	2>&1

  ) | stripColors | svlogd $datadir/log
) &

# After starting a session, make sure that svlogd is re-loaded in order
# to read the config file (woul not tdo it right on the start)
test yes != "$start" || {
    sleep 1
    pid=`get_pid_svlogd`
    test -z "$pid" || kill -HUP $pid
    echo
}

# Logging ...
test yes != "$logs" || {
  mkdir -p $datadir/log/
  touch $datadir/log/current |
  tail -F $datadir/log/current |

    # Filter out chaff on console data
    grep -v \
      -e '>> [NPF]' \
      -e '<< [NPF]'
}

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------
