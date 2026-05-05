/**
 * Surge 監控 - 棄用 ID，改用 URL 絕對匹配版
 */

let host = "gemini.google.com";

// 1. 去活躍連線 (Active) 裡翻找
$httpAPI("GET", "/v1/requests/active", {}, (activeData) => {
    let nodeName = "未知";
    let reqs = activeData.requests || [];

    // 倒序尋找，確保抓到最新的一筆
    for (let i = reqs.length - 1; i >= 0; i--) {
        // 直接比對 URL 有沒有包含 gemini.google.com
        if (reqs[i].URL && reqs[i].URL.includes(host)) {
            nodeName = reqs[i].policyName || "DIRECT";
            console.log("在 Active 抓到了！底層資料: " + JSON.stringify(reqs[i]));
            break;
        }
    }

    if (nodeName !== "未知") {
        $notification.post("Gemini 連線報告", "✅ Active 命中", "節點: " + nodeName);
        $done({});
    } else {
        // 2. 如果 Active 沒有，去歷史紀錄 (Recent) 裡翻找
        $httpAPI("GET", "/v1/requests/recent", {}, (recentData) => {
            let rReqs = recentData.requests || [];
            
            for (let i = rReqs.length - 1; i >= 0; i--) {
                if (rReqs[i].URL && rReqs[i].URL.includes(host)) {
                    nodeName = rReqs[i].policyName || "DIRECT";
                    console.log("在 Recent 抓到了！底層資料: " + JSON.stringify(rReqs[i]));
                    break;
                }
            }
            
            if (nodeName !== "未知") {
                $notification.post("Gemini 連線報告", "✅ Recent 命中", "節點: " + nodeName);
            } else {
                $notification.post("Gemini 失敗", "網址匹配失敗", "API 內找不到紀錄");
                console.log("API 查詢失敗。");
            }
            $done({});
        });
    }
});
