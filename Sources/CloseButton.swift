import AppKit
import ApplicationServices

enum KugouCloseButton {
    static let id = "com.kugou.mac.Music"

    // Catalyst can return a plain AXButton at a native traffic-light position.
    // Match the app's actual AXCloseButton geometry, never a fixed title-bar offset.
    static func exactHit(point:CGPoint, hit:CGRect, close:CGRect, window:CGRect) -> Bool {
        let values = [hit.minX,hit.minY,hit.width,hit.height,close.minX,close.minY,close.width,close.height]
        guard values.allSatisfy({$0.isFinite}), close.width > 0, close.height > 0,
              close.width <= 32, close.height <= 32,
              window.contains(close), close.contains(point), hit.contains(point) else {return false}
        return abs(hit.minX-close.minX) <= 0.5 && abs(hit.minY-close.minY) <= 0.5 &&
            abs(hit.width-close.width) <= 0.5 && abs(hit.height-close.height) <= 0.5
    }

    static func matches(hit:AXUIElement, point:CGPoint, pid:pid_t) -> Bool {
        func value(_ element:AXUIElement,_ key:String) -> CFTypeRef? {
            var result:CFTypeRef?
            guard AXUIElementCopyAttributeValue(element,key as CFString,&result) == .success else {return nil}
            return result
        }
        func frame(_ element:AXUIElement) -> CGRect? {
            guard let p=value(element,kAXPositionAttribute), let s=value(element,kAXSizeAttribute),
                  CFGetTypeID(p)==AXValueGetTypeID(), CFGetTypeID(s)==AXValueGetTypeID() else {return nil}
            var point=CGPoint.zero;var size=CGSize.zero
            guard AXValueGetValue(p as! AXValue,.cgPoint,&point), AXValueGetValue(s as! AXValue,.cgSize,&size) else {return nil}
            return CGRect(origin:point,size:size)
        }
        var hitPID:pid_t=0
        guard AXUIElementGetPid(hit,&hitPID) == .success, hitPID==pid,
              let app=NSRunningApplication(processIdentifier:pid), app.bundleIdentifier==id,
              !app.isHidden, !app.isTerminated,
              value(hit,kAXRoleAttribute) as? String == kAXButtonRole,
              value(hit,kAXEnabledAttribute) as? Bool == true, let hitFrame=frame(hit) else {return false}
        let application=AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application,0.05)
        guard let windows=value(application,kAXWindowsAttribute) as? [AXUIElement] else {return false}
        for window in windows.prefix(8) {
            guard value(window,kAXMinimizedAttribute) as? Bool == false,
                  let windowFrame=frame(window), windowFrame.contains(point),
                  let raw=value(window,kAXCloseButtonAttribute), CFGetTypeID(raw)==AXUIElementGetTypeID() else {continue}
            let close=raw as! AXUIElement
            guard value(close,kAXSubroleAttribute) as? String == kAXCloseButtonSubrole,
                  value(close,kAXEnabledAttribute) as? Bool == true, let closeFrame=frame(close) else {continue}
            if exactHit(point:point,hit:hitFrame,close:closeFrame,window:windowFrame) {return true}
        }
        return false
    }
}
