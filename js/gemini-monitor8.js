/**
 * Surge 監控 - 地毯式搜索版
 */

// 1. 強制檢查所有可能的屬性
let r = $request;
let pName = r.policyName || r.node || r.policy || "N/A";
let uName = r.url || r.URL || "N/A";

// 2. 這是最核心的除錯：把整個 $request 物件轉成字串印出來
// 這樣我們在 Output 就能看到到底有哪些 Key 可以用
console.log("--- 原始 $request 物件內容 ---");
console.log(JSON.stringify(r));
console.log("--- 結束 ---");

console.log("嘗試抓取的節點名: " + pName);

// 3. 只要抓到不是 N/A 或 DIRECT，就彈窗
if (pName !== "N/A" && pName !== "DIRECT") {
    $notification.post("Gemini 成功", uName, "真實節點: " + pName);
} else {
    // 即使是 DIRECT 也彈一個窗，用來確認通知功能是否正常
    $notification.post("DEBUG", "監控已觸發", "但目前抓到的是: " + pName);
}

$done({});
