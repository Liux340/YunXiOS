/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：全局限速器（令牌桶）。多分片共享同一实例，保证总速不超过设置上限。
 */

import Foundation

final class SpeedLimiter {

    private let lock = NSLock()
    private var tokens: Double = 0
    private var lastRefill = Date()
    /// 速率（字节/秒）；0 表示不限速
    private var rate: Double = 0

    /// 设置速率（字节/秒，0 = 不限速）
    func setRate(_ bytesPerSecond: Int64) {
        lock.lock()
        rate = Double(max(0, bytesPerSecond))
        tokens = 0
        lastRefill = Date()
        lock.unlock()
    }

    var currentRate: Int64 {
        lock.lock(); defer { lock.unlock() }
        return Int64(rate)
    }

    /// 消费额度；超出速率时挂起等待（桶容量 = 1 秒额度）
    func consume(_ bytes: Int) async {
        lock.lock()
        if rate <= 0 { lock.unlock(); return }
        let need = min(Double(bytes), rate)
        lock.unlock()

        while true {
            lock.lock()
            let now = Date()
            tokens = min(rate, tokens + now.timeIntervalSince(lastRefill) * rate)
            lastRefill = now
            if tokens >= need {
                tokens -= need
                let currentRate = rate
                lock.unlock()
                if currentRate <= 0 { return }
                return
            }
            let deficit = need - tokens
            let activeRate = rate
            lock.unlock()
            if activeRate <= 0 { return }
            let wait = max(0.01, min(deficit / activeRate, 0.2))
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }
}
