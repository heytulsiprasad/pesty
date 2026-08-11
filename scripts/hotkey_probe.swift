// Probe: does RegisterEventHotKey refuse a combination another *process* owns?
//
// It does not. Measured on macOS 26.2 (25C56), two processes registering the
// identical combination BOTH get noErr and BOTH get a live EventHotKeyRef:
//
//     pid=15981 status=0 eventHotKeyExistsErr=-9878 ref=set
//     pid=15993 status=0 eventHotKeyExistsErr=-9878 ref=set
//
// eventHotKeyExistsErr only appears for a duplicate registration within a single
// process, which HotKeyCenter.reload() rules out by unregistering first. So the
// return status can flag an outright API refusal, but it can never tell us that
// another app has claimed the shortcut. Keep the UI wording honest about that.
//
// Re-run after a macOS upgrade if that assumption starts to matter again:
//
//     swiftc -O scripts/hotkey_probe.swift -o /tmp/hotkey_probe
//     /tmp/hotkey_probe --hold &   # process 1 takes the combination
//     /tmp/hotkey_probe            # process 2 asks for the same one
import Carbon.HIToolbox
import Foundation

let keyCode = UInt32(kVK_F13)
let mods = UInt32(cmdKey | optionKey | controlKey | shiftKey)

var ref: EventHotKeyRef?
let id = EventHotKeyID(signature: OSType(0x54_45_53_54), id: 1)
let status = RegisterEventHotKey(keyCode, mods, id, GetApplicationEventTarget(), 0, &ref)

print("pid=\(getpid()) status=\(status) eventHotKeyExistsErr=\(eventHotKeyExistsErr) ref=\(ref == nil ? "nil" : "set")")
fflush(stdout)

if CommandLine.arguments.contains("--hold") {
    Thread.sleep(forTimeInterval: 25)
}
