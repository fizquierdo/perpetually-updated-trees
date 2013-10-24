#!/bin/sh
# Fernando Izquierdo Oct 2013 fer.izquierdo@gmail.com

# This script will check all requirements and do a minimal standalon installation of PUmPER
# No guarantees given

# If ruby is not available in your system, an installation with rvm will be attempted
echo -n "Testing ruby ... "
if ! command -v ruby > /dev/null 2>&1; then
   echo "ERROR: ruby not found"
   # This will install rvm (ruby version manager) in your system
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
fi
echo "OK"

# Call the generic PUmPER installation ruby script (standalone)
echo -n "Installing PUmPER dependencies ... "
scripts/install_dependencies.rb standalone
