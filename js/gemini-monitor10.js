/**
 * Surge 監控腳本 - 最終結合版
 */

let host = $request.hostname || "gemini.google.com";
let reqId = $request.id; // 這是剛剛日誌裡看到的連線身分證

// 呼叫 API 查節點。注意：第三個參數必須是 {}，不能是 null，否則腳本會直接崩潰導致沒通知！
$httpAPI("GET", "/v1/requests/recent", {}, (data) => {
    let nodeName = "未知節點 (API未命中)";

    // 在最近的連線紀錄中，用 ID 找出剛才那筆請求，並讀取 policyName
    if (data && data.requests) {
        let match = data.requests.find(r => r.id === reqId);
        if (match && match.policyName) {
            nodeName = match.policyName;
        }
    }

    // 強制打印日誌到 Output 面板，方便你事後檢查
    console.log("偵測到 Host: " + host);
    console.log("連線 ID: " + reqId);
    console.log("真實使用節點: " + nodeName);

    // 發送通知 (完全使用你原本會成功的格式)
    $notification.post("Gemini 連線報告", host, "✅ 節點: " + nodeName);

    // 確保腳本結束 (必須包在回調函數裡面)
    $done({});
});
