/**
 * Surge 監控腳本 - 策略偵測強化版
 */

// 1. 嘗試多個可能的屬性來獲取節點名稱
// $session.proxy 是官方推薦獲取最終決策節點的方式
let nodeName = $session.proxy || $request.node || $request.policy;

// 2. 獲取 Host
let host = $request.hostname || "gemini.google.com";

// 3. 如果拿不到節點名，或者拿到的是空的，我們就不發通知，避免干擾
if (!nodeName || nodeName === "DIRECT") {
    console.log("跳過通知：請求為直連或節點資訊未就緒 (" + host + ")");
    $done({});
} else {
    // 強制打印到 Output 面板方便檢查
    console.log("成功抓取！Host: " + host);
    console.log("真實節點: " + nodeName);

    // 發送通知
    $notification.post("Gemini 策略監控", host, "✅ 使用節點: " + nodeName);
    
    $done({});
}
