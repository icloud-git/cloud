/**
 * Surge 監控 - 最終冷卻防刷版 (60秒限制)
 */

let host = "gemini.google.com";

// 1. 讀取上次通知的時間（毫秒）與現在時間
let lastTime = $persistentStore.read("gemini_notify_time");
let now = Date.now();

// 2. 判斷是否在 60 秒 (60000 毫秒) 冷卻期內
if (lastTime && (now - parseInt(lastTime)) < 60000) {
    console.log("⏳ 冷卻中：距離上次通知未滿 60 秒，自動靜默。");
    // 直接結束腳本，連 API 都不去查，節省系統資源
    $done({});
} else {
    // 輔助函數：發送通知並將「現在時間」寫入資料庫記錄
    function triggerNotify(source, nodeName) {
        $notification.post("Gemini 節點監控", "", "✅ 節點: " + nodeName);
        // 寫入儲存空間，重置冷卻倒數
        $persistentStore.write(now.toString(), "gemini_notify_time");
        console.log("通知已發送，開始 60 秒冷卻。");
        $done({});
    }

    // 3. 去活躍連線 (Active) 裡翻找
    $httpAPI("GET", "/v1/requests/active", {}, (activeData) => {
        let reqs = activeData.requests || [];
        for (let i = reqs.length - 1; i >= 0; i--) {
            if (reqs[i].URL && reqs[i].URL.includes(host)) {
                triggerNotify("Active", reqs[i].policyName || "DIRECT");
                return;
            }
        }

        // 4. 去歷史紀錄 (Recent) 裡翻找
        $httpAPI("GET", "/v1/requests/recent", {}, (recentData) => {
            let rReqs = recentData.requests || [];
            for (let i = rReqs.length - 1; i >= 0; i--) {
                if (rReqs[i].URL && rReqs[i].URL.includes(host)) {
                    triggerNotify("Recent", rReqs[i].policyName || "DIRECT");
                    return;
                }
            }
            
            console.log("API 查詢找不到對應網址");
            $done({});
        });
    });
}
