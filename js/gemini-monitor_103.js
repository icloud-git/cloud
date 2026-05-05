/**
 * Surge 監控 - Active/Recent 雙保險精準命中版
 */

let reqId = $request.id;
let host = $request.hostname || "gemini.google.com";

function notify(nodeName) {
    // 成功抓到節點，發送通知
    $notification.post("Gemini 連線成功", host, "✅ 實際使用節點: " + nodeName);
    $done({});
}

// 1. 第一關：先查 Active (活躍連線) ⭐️ 因為通常網頁還在載入中
$httpAPI("GET", "/v1/requests/active", {}, (activeData) => {
    let found = false;
    
    if (activeData && activeData.requests) {
        let match = activeData.requests.find(r => r.id === reqId);
        if (match && match.policyName) {
            found = true;
            notify(match.policyName);
        }
    }

    // 2. 第二關：如果 Active 裡沒有，代表連線瞬間結束了，去 Recent (最近連線) 找
    if (!found) {
        $httpAPI("GET", "/v1/requests/recent", {}, (recentData) => {
            if (recentData && recentData.requests) {
                let match = recentData.requests.find(r => r.id === reqId);
                if (match && match.policyName) {
                    notify(match.policyName);
                    return; // 結束執行
                }
            }
            
            // 如果兩邊都沒找到 (極端情況)
            console.log("雙重 API 查詢皆未命中 ID: " + reqId);
            $notification.post("Gemini 監控", host, "⚠️ 無法解析節點名稱");
            $done({});
        });
    }
});
