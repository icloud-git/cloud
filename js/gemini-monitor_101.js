// 1. 基本資訊
let url = $request.url || "未知網址";

// 2. 破解 Surge 隱藏物件，強行抓出所有屬性名稱
let keys = Object.keys($request).join(", ");

// 3. 直接印在 Output 裡
console.log("--- 腳本執行成功 ---");
console.log("目標網址: " + url);
console.log("Surge 給了我們這些變數: " + keys);

// 4. 盲測一下幾個常見的節點變數
console.log("測試 policy: " + $request.policy);
console.log("測試 policyName: " + $request.policyName);
console.log("測試 node: " + $request.node);

// 5. 保證會彈出的通知
$notification.post("Gemini 腳本觸發", "請點開 Output 面板", "變數有: " + keys);

$done({});
