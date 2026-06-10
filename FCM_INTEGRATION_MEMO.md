# Q 潔淨後端 — FCM 推播整合說明

## 狀態

✅ **已整合** — CAN 後端已於 `POST /api/task`（民眾回報溢滿建立新任務）時自動發送 FCM 推播通知。

---

## 運作機制

### 觸發時機

當民眾透過 QR Code 掃描回報溢滿，後端成功建立**新任務**（非重複回報）時，自動發送 FCM 推播。

> 重複回報同一垃圾桶不會再次觸發推播。

### Topic 命名

為避免與立碼幫幫忙的 topic 衝突，Q 潔淨的 topic 加上 `can_` 前綴：

```
/topics/can_{stationCode}
```

例如 A12 站：`/topics/can_A12`

### FCM 配置

後端從 `src/app/fcm/fcm.config.ts` 讀取 Server Key：

```typescript
export const FCM_CONFIG = {
    serverKey: 'AAAA...your-server-key...',
    fcmUrl: 'https://fcm.googleapis.com/fcm/send',
};
```

- 若 `serverKey` 留空，FCM 推播會被**優雅跳過**，系統仍正常運作
- 發送失敗不影響主流程（Fire-and-forget 模式）

---

## FCM Payload 格式

後端實際發送的 payload：

```json
{
  "to": "/topics/can_A12",
  "notification": {
    "title": "垃圾桶溢滿回報",
    "body": "A12 站月台層北側垃圾桶已滿，請前往處理"
  },
  "data": {
    "system": "can",
    "station_code": "A12",
    "serial_number": "123",
    "location": "月台層北側",
    "is_full": "true"
  }
}
```

### 資料欄位說明

| 欄位 | 說明 |
|------|------|
| `data.system` | 固定為 `"can"`，App 用來區分系統 |
| `data.station_code` | 站點代碼 |
| `data.serial_number` | 任務序號（`serialNumber`） |
| `data.location` | 垃圾桶位置名稱 |
| `data.is_full` | 溢滿狀態（`"true"`） |

---

## App 端訂閱機制

CAN 登入回傳已包含 `topic` 欄位（例如 `"can_A12"`），App 直接使用該值訂閱，無需自行拼接：

```dart
// login response: { access_token, account, station, topic }
pushService.subscribeToTopic(user.topic)
```

兩套系統共享同一個 Firebase 專案與 `PushNotificationService` 實例：
- 立碼幫幫忙訂閱 `/topics/{stationCode}`（無前綴，後端決定）
- Q 潔淨訂閱 `/topics/can_{stationCode}`（後端在 login response 的 `topic` 欄位提供）

---

## 注意事項

1. **僅共用 Firebase Server Key，不共享任何資料庫或業務邏輯**。Q 潔淨依然是完全獨立的系統。
2. **推播內容請簡潔明瞭**，因為站務人員可能同時收到立碼幫幫忙和 Q 潔淨的通知。
3. **不要將敏感資訊放在 `data` payload 中**（例如帳號密碼、個資），因為 FCM data payload 在裝置上可被讀取。
4. **錯誤處理**：FCM API 呼叫失敗不影響 Q 潔淨業務邏輯的執行，使用 async / fire-and-forget 模式。

---

## 歷史版本

- **v1.0**（2024-06）：後端整合 FCM，於 `POST /api/task` 成功建立新任務時發送推播

如有疑問，請聯繫 App 端開發者確認 `data` payload 欄位需求。
