#!/usr/bin/env bash
# tn5250, the IBM i 5250 terminal (tn5250 and xt5250), as a system RPM from
# Fedora's own repositories: a host keeps it through `ujust migrate`, whose
# step 3 removes every layered package.
#
# Usage: run by build.sh; no arguments.
# Writes: the tn5250 package.
# Exit status: 0 done; dnf5's own status otherwise.

# shellcheck source=lib/env.sh
source "$(dirname "$(realpath "$0")")/lib/env.sh"

dnf5 -y install tn5250

log "tn5250: $(rpm -q --qf '%{VERSION}-%{RELEASE}' tn5250)"
