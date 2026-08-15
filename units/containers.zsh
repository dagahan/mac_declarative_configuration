requires=(software)

# The third plist in ~/Library/LaunchAgents, and the second that starts
# something. Everything else here is deliberately kept out of the directories
# launchd scans on its own, so a reboot brings nothing back — see the note in
# providers/daemon.zsh. This is an exception, asked for: colima is a daemon in
# the ordinary sense, the Docker socket every container in cimea_automation
# talks to, and a mac that logs in without it can only answer "the store would
# not start" to anything that wants a container.
#
# Not `daemon` with plist=, which is the managed form: that one is loaded only
# when a sync bootstraps it, which is the very thing this must not depend on.
#
# `colima start` returns as soon as the VM is up, so KeepAlive fires only on a
# non-zero exit — a login that raced the network retries a minute later, and a
# VM that came up is left alone rather than restarted forever.
file colima-login-agent from=config/launchd/colima.plist \
     at="$HOME/Library/LaunchAgents/com.mac-setup.colima.plist"
