//
//  DockHandoff.swift
//  Liftoff
//
//  把 App 從啟動台拖進 Dock：格線內的拖曳是我們自己用滑鼠事件模擬的（見 LaunchpadModel+Input），
//  系統看不到，所以游標一進到 Dock 所在的螢幕邊緣，就把這次拖曳交接成系統拖曳（NSDraggingSession，
//  pasteboard 放 App 的檔案 URL）。Dock 本來就接受從 Finder 拖來的 .app，放開即加入，與經典啟動台相同。
//
//  效能：Dock 區域每次拖曳只在第一次需要時算一次（讀兩個 Dock 偏好 + 螢幕 frame，微秒級），
//  之後每個滑鼠事件只是一次矩形包含判斷；沒有拖曳時完全不執行。
//

import AppKit

/// Dock 在螢幕上的感應區（螢幕座標，左下為原點）。
struct DockZone: Equatable {
    enum Side: String {
        case bottom, left, right
    }

    /// 游標進入就交接給系統拖曳的區域
    let rect: CGRect
    /// Dock 所在的螢幕邊
    let side: Side
    /// Dock 平時是藏起來的（自動隱藏）：要靠游標在拖曳中「進入」螢幕邊緣才會滑出來
    let needsReveal: Bool

    /// 細條感應帶厚度：Dock 自己的顯示觸發區約 2–4pt
    private static let edgeThickness: CGFloat = 4
    /// Dock 看不到時底部感應帶的厚度：要在游標碰到邊緣「之前」交接，之後繼續往下拖才算進入邊緣、Dock 才會滑出
    /// （實測交接時游標已貼邊，之後怎麼往下推 Dock 都不出來）。左右側不加寬，以免搶走拖到邊緣翻頁
    private static let approachThickness: CGFloat = 32

    /// 計算指定螢幕上的 Dock 感應區。
    /// - Parameters:
    ///   - screen: 啟動台所在的螢幕
    ///   - coversDock: 啟動台是否蓋住 Dock
    /// - Returns: 感應區；Dock 不在這個螢幕、也沒有自動隱藏時回傳 nil
    static func current(on screen: NSScreen, coversDock: Bool) -> DockZone? {
        // 「各螢幕有獨立空間」關閉時 Dock 只待在主螢幕，其他螢幕的邊緣叫不出 Dock
        let dockCanBeHere = NSScreen.screensHaveSeparateSpaces || screen == NSScreen.screens.first
        return make(frame: screen.frame, visible: screen.visibleFrame, coversDock: coversDock,
                    autohide: dockCanBeHere && (preference("autohide") as? Bool ?? false),
                    orientation: preference("orientation") as? String ?? "bottom")
    }

    /// 純幾何版本（測試用）：由螢幕 frame、visibleFrame 與 Dock 偏好算出感應區。
    /// - Parameters:
    ///   - frame: 螢幕 frame
    ///   - visible: 螢幕 visibleFrame（已扣掉選單列與常駐顯示的 Dock）
    ///   - coversDock: 啟動台是否蓋住 Dock（蓋住時 Dock 看不到，改用靠邊的感應帶）
    ///   - autohide: Dock 是否自動隱藏
    ///   - orientation: Dock 方向偏好（bottom／left／right）
    /// - Returns: 感應區，沒有時為 nil
    static func make(frame: CGRect, visible: CGRect, coversDock: Bool, autohide: Bool, orientation: String) -> DockZone? {
        // visibleFrame 扣掉的就是常駐顯示的 Dock（上方另有選單列，不列入）
        let insets: [(side: Side, size: CGFloat)] = [
            (.bottom, visible.minY - frame.minY),
            (.left, visible.minX - frame.minX),
            (.right, frame.maxX - visible.maxX),
        ]
        if let shown = insets.max(by: { $0.size < $1.size }), shown.size > edgeThickness {
            let thickness = coversDock ? edgeBand(shown.side) : shown.size
            return DockZone(rect: strip(shown.side, thickness: thickness, in: frame), side: shown.side, needsReveal: false)
        }
        // 自動隱藏：visibleFrame 幾乎不扣，改用偏好設定的方向
        guard autohide else { return nil }
        let side = Side(rawValue: orientation) ?? .bottom
        return DockZone(rect: strip(side, thickness: edgeBand(side), in: frame), side: side, needsReveal: true)
    }

    /// Dock 看不到時的感應帶厚度：底部加寬，左右維持細條。
    private static func edgeBand(_ side: Side) -> CGFloat {
        side == .bottom ? approachThickness : edgeThickness
    }

    /// 螢幕某一邊的長條區域。
    private static func strip(_ side: Side, thickness: CGFloat, in frame: CGRect) -> CGRect {
        switch side {
        case .left: CGRect(x: frame.minX, y: frame.minY, width: thickness, height: frame.height)
        case .right: CGRect(x: frame.maxX - thickness, y: frame.minY, width: thickness, height: frame.height)
        case .bottom: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: thickness)
        }
    }

    /// 游標貼在 Dock 那一邊時，往內退一點的位置（螢幕座標）；沒貼邊時回傳 nil。
    /// 自動隱藏的 Dock 只在游標「進入」邊緣時滑出，交接當下已貼邊就得先退開，使用者接著往外拖才會叫出 Dock。
    /// - Parameters:
    ///   - point: 游標位置（螢幕座標）
    ///   - frame: 所在螢幕的 frame
    /// - Returns: 退開後的位置
    func pulledBack(_ point: CGPoint, in frame: CGRect) -> CGPoint? {
        let margin: CGFloat = 2, pull: CGFloat = 8
        switch side {
        case .bottom: return point.y < frame.minY + margin ? CGPoint(x: point.x, y: frame.minY + pull) : nil
        case .left: return point.x < frame.minX + margin ? CGPoint(x: frame.minX + pull, y: point.y) : nil
        case .right: return point.x > frame.maxX - margin ? CGPoint(x: frame.maxX - pull, y: point.y) : nil
        }
    }

    private static func preference(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString)
    }
}

/// 系統拖曳的來源：只允許「連結」——Dock 據此把 App 加成圖示，原本的 App 不論放到 Dock 哪裡都不會被搬走、拷貝或刪除。
/// 實測：給 .copy 時放到 Dock 右側的資料夾堆疊會把整個 App 拷貝進那個資料夾；給 .move／.generic／.delete
/// 則會搬走或丟進垃圾桶。這個遮罩只在拖曳開始時被問一次，沒辦法依游標位置動態切換。
final class DockDragSource: NSObject, NSDraggingSource {
    /// 拖曳結束（不論有沒有放進 Dock）時呼叫
    var onEnd: (() -> Void)?

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .link : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onEnd?()
    }
}
