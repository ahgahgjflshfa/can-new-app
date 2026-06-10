# Q 潔淨後端 — 新增 FCM 推播整合說明

## 背景

目前「立碼幫幫忙」App 已使用 Firebase Cloud Messaging（FCM）接收即時推播。現在需要讓同一個 App 同時也能接收 **Q 潔淨（CAN 垃圾桶溢滿系統）** 的推播通知，讓站務人員能在單一 App 內處理兩邊的任務。

**關鍵前提**：兩個系統的後端保持獨立，不共享資料庫與業務邏輯，**僅共享同一個 Firebase 專案的 Server Key** 用來發送推播。

---

## 你需要做的事

### 1. 取得立碼幫幫忙 Firebase 專案的 Server Key

- 請聯繫立碼幫幫忙後端團隊，取得 FCM Server Key（或 Cloud Messaging API 的 OAuth 2.0 存取權杖）。
- 這個 Key 用來呼叫 Firebase HTTP API：`https://fcm.googleapis.com/fcm/send`

### 2. 在「民眾回報溢滿」或「任務建立」時發送推播

Q 潔淨在以下情境需要發送 FCM 推播（擇一或兩者都發）：
- `POST /api/task`（民眾回報溢滿，建立新任務）
- `PATCH /api/trash-bin/full-state/:code`（站務人員標記垃圾桶為滿）

建議在任務狀態變為「未完成 / 待處理」時觸發。

### 3. FCM Payload 格式

呼叫 Firebase HTTP API 時，請使用以下 payload 格式：

```json
{
  "to": "/topics/{stationCode}",
  "notification": {
    "title": "垃圾桶溢滿回報",
    "body": "{stationName} {locationName} 垃圾桶已滿，請前往處理"
  },
  "data": {
    "system": "can",
    "station_code": "A12",
    "serial_number": "TASK-20240609-001",
    "location": "月台層北側",
    "is_full": "true"
  }
}
```

**重要欄位說明**：

| 欄位 | 必填 | 說明 |
|------|------|------|
| `notification.title` | 是 | 推播標題，App 會顯示在通知列 |
| `notification.body` | 是 | 推播內容，建議包含站點名稱與位置 |
| `data.system` | **是** | 必須固定為 `"can"`，App 用來區分這是 Q 潔淨系統的推播 |
| `data.station_code` | 是 | 站點代碼，App 訂閱 topic 時會用到 |
| `data.serial_number` | 是 | 任務唯一編號，App 點擊推播後會導航到該任務 |
| `data.location` | 建議 | 垃圾桶位置描述，方便站務人員辨識 |
| `data.is_full` | 建議 | 溢滿狀態（`"true"` / `"false"`）|

### 4. Topic 命名規則

與立碼幫幫忙保持一致：**topic = station_code（站點代碼）**。例如 `/topics/A12`。

App 端會在登入 Q 潔淨系統後，呼叫 `subscribeToTopic(stationCode)` 訂閱對應站點。

---

## 完整範例：使用 cURL 發送 FCM 推播

```bash
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "/topics/A12",
    "notification": {
      "title": "垃圾桶溢滿回報",
      "body": "A12 站月台層北側垃圾桶已滿，請前往處理"
    },
    "data": {
      "system": "can",
      "station_code": "A12",
      "serial_number": "TASK-20240609-001",
      "location": "月台層北側",
      "is_full": "true"
    }
  }'
```

---

## 注意事項

1. **僅共用 Firebase Server Key，不共享任何資料庫或業務邏輯**。Q 潔淨依然是完全獨立的系統。
2. **推播內容請簡潔明瞭**，因為站務人員可能同時收到立碼幫幫忙和 Q 潔淨的通知。
3. **不要將敏感資訊放在 `data` payload 中**（例如帳號密碼、個資），因為 FCM data payload 在裝置上可被讀取。
4. **錯誤處理**：FCM API 呼叫失敗不應影響 Q 潔淨業務邏輯的執行，建議使用 async / fire-and-forget 模式。

---

## 與 App 端整合時程

1. 你這邊先加上 FCM 發送邏輯（預估 1 天）
2. App 端同步實作雙系統支援（系統選擇畫面、推播導航、Q 潔淨任務畫面）
3. 整合測試：用測試帳號登入 Q 潔淨，建立任務，確認 App 收到推播並能正確導航

如有疑問，請直接聯繫 App 端開發者確認 `data` payload 欄位需求。
