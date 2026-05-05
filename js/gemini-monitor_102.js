/**
 * Surge 監控 - 最終收網版 (基於 ID 查詢)
 */

let reqId = $request.id;
let host = $request.hostname || "gemini.google.com";

console.log("開始查詢連線 ID: " + reqId);

// 呼叫 Surge 內建 API，查詢最近的網路請求紀錄
$httpAPI("GET", "/v1/requests/recent", {}, (data) => {
    try {
        let nodeName = "未知節點";
        
        // 確保有抓到紀錄
        if (data && data.requests) {
            // 用我們的身分證 (reqId) 去茫茫紀錄中尋找剛才那筆連線
            let match = data.requests.find(r => r.id === reqId);
            
            if (match) {
                // 抓出真實的策略/節點名稱
                nodeName = match.policyName || "DIRECT";
                console.log("🎉 比對成功！真實節點為: " + nodeName);
            } else {
                console.log("⚠️ 找不到對應的 ID 紀錄");
            }
        }

        // 發送最終的彈窗通知
        $notification.post("Gemini 連線報告", host, "✅ 使用節點: " + nodeName);

    } catch (e) {
        console.log("腳本解析出錯: " + e);
    } finally {
        // 確保腳本完美結束
        $done({});
    }
});
