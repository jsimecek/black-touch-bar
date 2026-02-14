#!/bin/bash
#
# Toggle the Touch Bar blackout.
# Starts BlackTouchBar.app if needed, then sends it a toggle notification.
#

APP="$HOME/Applications/BlackTouchBar.app"

pgrep -x BlackTouchBar > /dev/null 2>&1 || { open "$APP" && sleep 1; }

/usr/bin/swift -e '
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    NSNotification.Name("com.local.BlackTouchBar.toggle"), object: nil)
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
'
