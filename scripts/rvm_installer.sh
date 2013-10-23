#!/bin/sh
# Fernando Izquierdo Oct 2013 fer.izquierdo@gmail.com

# This will install rvm (ruby version manager) in your system, as well as a suitable ruby version for PUmPER. You can then use this as a default to run PUmPER.
# For details of what this will do, check:
# https://rvm.io/rvm/install
# No guarantees given



# Install a ruby version manager (rvm) 
echo -n "Testing rvm ... "
if ! command -v rvm > /dev/null 2>&1; then
  echo -n "Testing curl ... "
  if ! command -v curl > /dev/null 2>&1; then
     echo "ERROR: curl not found"
     exit
  fi
  echo "OK"
  \curl -L https://get.rvm.io | bash
fi
echo "OK"

rvm reload

# Use rvm to install locally  Ruby version 1.9.3
command rvm install 1.9.3
