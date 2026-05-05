/**
 * Surge 節點監控腳本 (Response 增強版)
 */

// 1. 優先從 $session.proxy 獲取節點名稱
// 2. 如果為空，嘗試從內部狀態獲取
let nodeName = $session.proxy || "直接連線 (DIRECT)";

// 獲取主機名
let host = $request.hostname || "gemini.google.com";

// 發送通知
$notification.post("Gemini 連線報告", host, "✅ 經由節點: " + nodeName);

// 必須呼叫 $done
$done({});
