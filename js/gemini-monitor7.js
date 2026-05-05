/**
 * Surge 監控腳本 - 真實 HTTP API 查詢版
 */

let host = $request.hostname || "gemini.google.com";

// 呼叫 Surge 內部 API 獲取最近的請求清單
// 這不會產生外部網路請求，只會問 Surge 自己的核心引擎
$httpAPI("GET", "/v1/requests/recent", null, (data) => {
    try {
        let requests = data.requests || [];
        let realNode = "未找到節點";

        // 從最新的請求開始往回找，找到有 gemini.google.com 的那筆紀錄
        for (let i = requests.length - 1; i >= 0; i--) {
            let req = requests[i];
            // 確保 URL 存在且符合我們的目標
            if (req.URL && req.URL.indexOf(host) !== -1) {
                // Surge 會把該請求使用的策略/節點記錄在 policyName
                realNode = req.policyName || "未知";
                
                // 把該請求的詳細資訊印在 Log，方便如果名稱不如預期時可以除錯
                console.log("找到目標請求，底層資訊：" + JSON.stringify(req));
                break;
            }
        }

        console.log("解析出真實節點: " + realNode);

        // 過濾掉直連或沒抓到的情況，避免煩人彈窗
        if (realNode === "DIRECT" || realNode === "未找到節點") {
            console.log("直連或未命中，不發通知");
        } else {
            // 發送通知
            $notification.post("Gemini 連線報告", host, "✅ 真實節點: " + realNode);
        }

        // 必須在異步回調內呼叫 $done
        $done({});

    } catch (error) {
        console.log("腳本執行出錯: " + error);
        $done({});
    }
});
