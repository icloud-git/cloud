/**
 * Surge 節點監控腳本 - Gemini 專用
 */

// 獲取當前請求使用的策略/節點名稱
// 在 http-request 類型腳本中，$session.proxy 會返回 Surge 最終決定的節點名
let policy = $session.proxy || "DIRECT (直連)";

// 獲取訪問的 Host
let host = $request.hostname || "gemini.google.com";

// 發送通知
$notification.post(
  "Gemini 策略監控", 
  `目標: ${host}`, 
  `當前連線使用節點: ${policy}`
);

// 腳本必須呼叫 $done() 以恢復請求執行
$done({});
