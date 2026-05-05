/**
 * Surge 節點監控腳本 - 兼容版
 */

// 獲取當前請求決策的策略/節點名稱
// 在 Surge 腳本中，可以透過 $request.node 獲取節點名
let nodeName = $request.node || "未知節點/DIRECT";

// 獲取主機名
let host = $request.hostname || "gemini.google.com";

// 發送通知
$notification.post("Gemini 監控", host, "使用節點: " + nodeName);

// 腳本必須呼叫 $done
$done({});
