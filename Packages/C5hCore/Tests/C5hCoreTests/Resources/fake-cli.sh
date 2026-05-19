#!/bin/bash
# Test fixture used by CommandRunner tests.
# Modes:
#   succeed                — exit 0, write to stdout
#   fail [code]            — exit code (default 1), write to stderr
#   sleep <seconds>        — sleep then exit 0
#   spam <bytes>           — write N bytes to stdout
#   echo-stderr <msg>      — write msg to stderr, exit 0
#   echo-env <VAR>         — print env var to stdout
#   pwd                    — print current working directory
case "$1" in
  succeed)
    echo "fake-cli ok" ;;
  fail)
    code="${2:-1}"
    echo "fake-cli fail" 1>&2
    exit "$code" ;;
  sleep)
    sleep "${2:-1}" ;;
  spam)
    head -c "${2:-1024}" /dev/urandom | base64 ;;
  echo-stderr)
    shift
    echo "$*" 1>&2 ;;
  echo-env)
    eval "echo \$$2" ;;
  pwd)
    pwd ;;
  *)
    echo "fake-cli: usage: succeed|fail|sleep|spam|echo-stderr|echo-env|pwd" 1>&2
    exit 2 ;;
esac
