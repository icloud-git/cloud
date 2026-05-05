/**
 * 監控 Gemini 連線節點
 */

// 獲取當前請求的域名
let host = $request.hostname;

// 獲取 Surge 為此請求分配的決策路徑 (Policy)
// $session 包含此請求的所有底層資訊
let policy = $session.proxy ? $session.proxy : "直接連線 (DIRECT)";

// 彈出通知
$notification.post("Gemini 連線監控", host, "使用節點: " + policy);

// 必須呼叫 $done() 以免請求被掛起
$done({});
