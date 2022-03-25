#! /bin/sh

self=${GETH_SESSION_SELF:-`basename "$0"`}

# Network name (used below for easy setup)
name=${GETH_SESSION_NAME:-ropsten}

# Digits, instance id appended to directory name
instance=${GETH_SESSION_INSTANCE:-0}

# Unique geth TCP/UDP communication port => base_port + instance
base_port=${GETH_SESSION_BASE_PORT:-30303}

# Geth sync mode, full, snap, or light
syncmode=${GETH_SESSION_SYNCMODE:-full}

# Git branch to use with "build" command
case "$name" in
kiln) git_branch=${GETH_GIT_BRANCH:-merge-kiln-v2} ;;
*)    git_branch=${GETH_GIT_BRANCH:-master}
esac

# Unique log data and database folder (relative to current directory)
datadir=${GETH_SESSION_DATADIR:-./datadir-geth-$name$instance}

# Enable local Geth services
server_api=${GETH_SERVER_API:-no}

# Adding generic options
# optargs=${GETH_SESSION_OPTARGS:-'--nat=none'}
# optargs=${GETH_SESSION_OPTARGS:-"$optargs xxxxx"}

# ------------------------------------------------------------------------------
# No need to change, below
# ------------------------------------------------------------------------------

# Geth server interface
test yes != $server_api || {
    optargs="$optargs --ws"
    optargs="$optargs --http"
    optargs="$optargs --ws.api=engine,eth,web3,net,debug"
    optargs="$optargs --http.api=engine,eth,web3,net,debug"
    optargs="$optargs --http.corsdomain=*"
    optargs="$optargs --authrpc.jwtsecret=./jwtsecret"
    optargs="$optargs --http.port=`expr    8545 + $instance \* 10`"
    optargs="$optargs --ws.port=`expr      8546 + $instance \* 10`"
    optargs="$optargs --authrpc.port=`expr 8551 + $instance \* 10`"
}

# Unique geth TCP/UDP communication port
port=`expr $base_port + $instance`

# Fixed session keys depending on port
session_key=`echo $port |
  awk '{for(n=0;n<32;n++){a=a"10"}print substr(a$1,1+length($1))}'`

# Name of custom genesis
genesis_json=geth-$name.json

# Per-network bootstrap nodes
enodes_kiln="enode://c354db99124f0faf677ff0e75c3cbbd568b2febc186af664e0c51ac435609badedc67a18a63adb64dacc1780a28dcefebfc29b83fd1a3f4aa3c0eb161364cf94@164.92.130.5:30303"

# Log spooler capacity settings
logfile_max=80000000
num_backlogs=40

# Base directory for finding objects in the Geth file system
find_prefix="`dirname $0` . .. ../.. go-ethereum nimbus-eth1-blobs"

# Sub-find directory for various items
find_geth=". .. build/bin"
find_genesis=". .. custom-network"

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

# Find pid of running svlogd and geth command
get_pids() {
    ps x|
	grep \
	    -e "geth --datadir=./data --port=$port" \
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
      logs    resume console logging (as descibed above)
      flush   delete all log and blockchain data
      build   re-compile geth version

   Mutually exclusive commands:
      stop    stop the Geth session (as descibed above)
      start   start the Geth session in the foreground
      daemon  background session (without termninating on logout, e.g. from ssh)
      enode   print enode of running geth
      attach  attach console to running Geth
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
    make geth
) || exit

# Print enode of other session
test yes != "$enode" || {
    geth=`find_exe geth $find_geth`
    echo admin.nodeInfo |
	$geth --datadir "$datadir/data" attach |
	sed \
	    -e '/enode:/!d' \
	    -e 's/^[^"]*"\(.*\)".*/\1/'
    exit
}

# Attach console to other session
test yes != "$enode" || {
    geth=`find_exe geth $find_geth`
    set -x
    $geth --datadir "$datadir/data" attach
    exit
}

# Start a new geth session in the background
test yes != "$start" || (
  mkdir -p $datadir/log $datadir/data

  geth=`find_exe geth $find_geth`
  init_data=no

  case "$name" in
  kiln)
      optargs="$optargs --networkid=1337802"
      optargs="$optargs --bootnodes=$enodes_kiln"
      init_data=yes
      ;;
  *)  optargs="$optargs --$name"
  esac

  # RPC authorisation seed, might not be needed though
  test -s "$datadir/jwtsecret" || (
      umask 377
      rm -f "$datadir/jwtsecret"
      {
	  openssl rand -hex 32
	  # echo $session_key
      } | tr -d '\n' > "$datadir/jwtsecret"
  )
  # Initialise genesis on data store
  test yes != "$init_data" || {
      test -d "$datadir/data/$name" || (
	  genesis=`find_file $genesis_json $find_genesis`
	  set -x
	  $geth init "$genesis" --datadir "$datadir/data" 
      )
  }

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
    ${geth:-geth} \
	--datadir=./data \
	--port=$port \
	--syncmode=$syncmode \
	$optargs \
	--nodekeyhex="$session_key" \
	--verbosity=5 \
	--log.debug \
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
