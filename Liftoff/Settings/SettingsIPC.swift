//
//  SettingsIPC.swift
//  Liftoff
//
//  主程式與「設定 process」之間的訊息格式（兩邊共用）。
//
//  為什麼設定頁要跑在另一個 process：SwiftUI 設定頁第一次顯示會留下約 13–17MB 的框架永久快取
//  （Swift metadata、objc 方法快取、SF Symbols 向量圖）與它們造成的 malloc 碎片，同一個 process 內收不回來
//  （2026-10-08 實測，見 docs/context/journal/process.md）。設定頁改由同一個執行檔以 `--settings-process <主程式 pid>`
//  另開一個實例，關掉視窗就整個結束，記憶體全數還給系統。
//
//  兩邊怎麼溝通：
//  - 設定值：照舊寫 UserDefaults（同一個 bundle ID 共用同一個網域），另一邊以 KVO 收到後重新讀取（`AppSettings.startExternalSync`）
//  - 需要主程式動手的事（版面整理、備份、暫停快速鍵）：Distributed Notification，`deliverImmediately` 讓背景中的主程式也立即收到
//  訊息都帶目標 pid：開發時 build 資料夾與 /Applications 的 Liftoff 可能同時執行，只處理給自己的。
//

import Foundation

nonisolated enum SettingsIPC {
    /// 設定 process 的啟動參數，後面接主程式 pid
    static let processFlag = "--settings-process"
    /// 設定 process → 主程式的請求
    static let requestName = Notification.Name("com.firstfu.Liftoff.settings.request")
    /// 主程式 → 設定 process 的回覆與狀態
    static let replyName = Notification.Name("com.firstfu.Liftoff.settings.reply")

    /// userInfo 的欄位名稱
    enum Field {
        static let target = "target", sender = "sender", id = "id", command = "command"
        static let argument = "argument", error = "error", hotKeyRegistered = "hotKeyRegistered"
    }

    /// 設定 process 請主程式做的事。
    enum Command: String, Sendable {
        /// 快速鍵錄製開始：先取消全域快速鍵，避免按到現有組合時直接打開啟動台
        case pauseHotKey
        /// 快速鍵錄製結束：依目前設定重新註冊
        case resumeHotKey
        /// 回報目前狀態（快速鍵是否註冊成功）
        case state
        /// 填滿各頁空位
        case compact
        /// 依名稱重新排列
        case alphabetical
        /// 匯入舊版啟動台的排列
        case importLegacy
        /// 智慧整理
        case organize
        /// 立即備份目前排列
        case backup
        /// 還原備份（argument 為備份檔路徑）
        case restore
        /// 轉交外部控制網址（argument 為網址）：設定 process 收到 liftoff:// 或 Dock 重開時交給主程式處理
        case openURL
        /// 把設定視窗帶到最前（主程式再次被要求打開設定時）
        case focus
    }

    /// 設定 process 的參數裡帶的主程式 pid；不是設定 process 時為 nil。
    static var hostPID: pid_t? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: processFlag), index + 1 < arguments.count else { return nil }
        return pid_t(arguments[index + 1])
    }

    /// 送出一則訊息。
    /// - Parameters:
    ///   - name: `requestName` 或 `replyName`
    ///   - target: 收件的 pid
    ///   - fields: 其餘欄位（必須是 property list 型別）
    static func post(_ name: Notification.Name, to target: pid_t, _ fields: [String: Any]) {
        var info = fields
        info[Field.target] = Int(target)
        info[Field.sender] = Int(getpid())
        // 主程式在設定視窗開著時不是前景 App，系統預設會暫停投遞給它，必須要求立即投遞
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: info, deliverImmediately: true)
    }

    /// 監看另一個 process 結束（含被強制結束）。
    ///
    /// 不用 `NSWorkspace.didTerminateApplicationNotification`：實測同一個 App 的另一個實例結束時（⌘W 正常結束或 kill -9）
    /// 都收不到這個通知；核心的 process 結束事件一定會來。
    /// - Parameters:
    ///   - pid: 要監看的 process
    ///   - handler: 結束後在主執行緒呼叫一次
    /// - Returns: 監看來源，呼叫端需持有，釋放即停止監看
    static func watchExit(of pid: pid_t, handler: @escaping @MainActor () -> Void) -> DispatchSourceProcess {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler {
            source.cancel()
            MainActor.assumeIsolated { handler() }
        }
        source.resume()
        return source
    }

    /// 取出給本 process 的訊息內容；不是給自己的回傳 nil。
    static func fields(of notification: Notification) -> [String: Any]? {
        guard let info = notification.userInfo as? [String: Any],
              info[Field.target] as? Int == Int(getpid()) else { return nil }
        return info
    }
}
