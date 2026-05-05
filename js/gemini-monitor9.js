/**
 * Surge 監控 - 真實節點 ID 匹配版
 */

// 獲取當前請求的唯一身分證和網域
let reqId = $request.id; 
let host = $request.hostname || "gemini.google.com";

// 輔助函數：發送通知
function notifyNode(nodeName) {
    if (nodeName && nodeName !== "DIRECT" && nodeName !== "REJECT") {
        $notification.post("Gemini 連線成功", "🎯 實際使用節點: " + nodeName, "目標: " + host);
    } else {
        console.log("直連或攔截，跳過通知: " + nodeName);
    }
    $done({});
}

// 1. 先去 Surge 的「活躍連線清單」中尋找這個 ID
$httpAPI("GET", "/v1/requests/active", null, (activeData) => {
    let reqs = activeData.requests || [];
    let match = reqs.find(r => r.id === reqId); // 用 ID 絕對精準匹配
    
    if (match && match.policyName) {
        console.log("在 Active 找到節點: " + match.policyName);
        notifyNode(match.policyName);
    } else {
        // 2. 如果剛好已經傳輸完畢，就去「最近連線清單」中找
        $httpAPI("GET", "/v1/requests/recent", null, (recentData) => {
            let rReqs = recentData.requests || [];
            let rMatch = rReqs.find(r => r.id === reqId);
            
            if (rMatch && rMatch.policyName) {
                console.log("在 Recent 找到節點: " + rMatch.policyName);
                notifyNode(rMatch.policyName);
            } else {
                console.log("API 查詢不到對應的紀錄 ID: " + reqId);
                $done({});
            }
        });
    }
});
