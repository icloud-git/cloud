/**
 * Surge 監控腳本 - 修正版
 */

// 直接從 $request 獲取對象
// 注意：Surge Mac 在 http-response 階段會將選中節點存於 $request.node 或 $request.policy
let nodeName = $request.node || $request.policy || "DIRECT";
let host = $request.hostname || "gemini.google.com";

// 強制打印日誌到 Output 面板
console.log("偵測到 Host: " + host);
console.log("使用節點: " + nodeName);

// 發送通知
$notification.post("Gemini 連線報告", host, "✅ 節點: " + nodeName);

// 確保腳本結束
$done({});
