/**
 * Surge 監控腳本 - 終極穩定版
 */

// 獲取基本資訊
let host = $request.hostname || "gemini.google.com";

// 使用 $httpAPI 獲取當前決策 (這是最準確的方式)
$httpAPI("GET", "/v1/policies/decisions", {}, (result) => {
    // 從所有決策中找到與當前請求相關的策略
    // 預設先抓 $request.node，若無則顯示 DIRECT
    let nodeName = $request.node || "DIRECT";
    
    // 強制在 Log 中打印，方便你檢查
    console.log("偵測到連線 Host: " + host);
    console.log("使用節點: " + nodeName);

    // 發送通知
    $notification.post("Gemini 連線報告", host, "✅ 節點: " + nodeName);
    
    // 異步回調中完成腳本
    $done({});
});
