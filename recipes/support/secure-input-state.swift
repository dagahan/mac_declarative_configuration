// The authoritative answer. ioreg's kCGSSessionSecureInputPID only records which
// process most recently *enabled* Secure Input — it goes stale when that process
// dies, so it says nothing about whether the block is live right now.
import Carbon
import Foundation
print(IsSecureEventInputEnabled() ? "ON" : "OFF")
