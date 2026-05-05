/**
 * Surge 監控 - Header 直接讀取版
 */

let resHeaders = $response.headers;
let reqHeaders = $request.headers;
let host = $request.hostname || "gemini.google.com";

// 1. 在 Surge 的除錯模式下，它可能會將策略寫入某些特定的 Header
// 我們把所有可能的 X-Surge 標頭都掃一遍
let nodeName = "未知節點";

// 檢查 Response Headers
if (resHeaders) {
    // 尋找 key 包含 surge 或 policy 的 header (不分大小寫)
    for (let key in resHeaders) {
        if (key.toLowerCase().includes('surge-policy') || key.toLowerCase().includes('surge-node')) {
            nodeName = resHeaders[key];
            break;
        }
    }
}

// 檢查 Request Headers (有時 Surge 會塞在這裡)
if (nodeName === "未知節點" && reqHeaders) {
    for (let key in reqHeaders) {
        if (key.toLowerCase().includes('surge-policy') || key.toLowerCase().includes('surge-node')) {
            nodeName = reqHeaders[key];
            break;
        }
    }
}

// 2. 如果還是找不到，我們直接把所有 Header 的 Key 印出來看看到底有沒有
let allKeys = [];
if (resHeaders) allKeys = allKeys.concat(Object.keys(resHeaders));
if (reqHeaders) allKeys = allKeys.concat(Object.keys(reqHeaders));

console.log("尋找節點結果: " + nodeName);
console.log("當前所有的 Headers Key: " + allKeys.join(", "));

// 3. 發送通知
if (nodeName !== "未知節點") {
    $notification.post("Gemini 連線成功", host, "✅ 節點: " + nodeName);
} else {
    $notification.post("除錯", host, "Header 裡沒有 Surge 標記，請看 Output");
}

$done({});
