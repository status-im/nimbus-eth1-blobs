#! /bin/sh

self=`basename "$0"`
default_branch=master

usage() {
  echo "Usage: $self [<branch>] [NIMFLAGS=--debugger:native]" >&2
  exit 2
}

case "$1" in
*=*|'') branch=$default_branch ;;
-*|\?*) usage ;;
*)      branch=${1:-$default_branch}; shift
esac

parking=parking-lsnglawngflnswfslkmlknm
make_flags="$*"

test "x$branch" != "x$parking" ||
  parking="free-$parking"

(
  set +e
  exec >/dev/null 2>&1
  git branch -D "$parking"
  git branch    "$parking"
  git checkout  "$parking"
  git branch -D "$branch"
  true
) && (
  set -ex
  git fetch --all
  git checkout "$branch"
  git branch -D "$parking"
  make -j2 nimbus $make_flags
) &&
  echo "*** finished " `date`

# End
