# TYM Metro CAN API 清單

本文件列出 TYM Metro CAN（垃圾桶溢滿回報系統）後端的所有 REST API 端點。

---

## 基本資訊

| 項目 | 值 | 備註 |
|------|-----|------|
| **Base URL** | `https://www.tymetro.com.tw/api` | 生產環境（從 CORS 設定推斷） |
| | `http://localhost:3001/api` | 本地開發 |
| **API 前綴** | `/api` | 所有路由均帶此前綴 |
| **認證方式** | JWT Bearer Token | `Authorization: Bearer <token>` |
| **Super Token** | `4pb9gsa196wFe9zo` | 可繞過認證（應於生產移除） |

---

## FCM 推播整合

Q 潔淨後端已整合 Firebase Cloud Messaging（FCM），在民眾回報溢滿（`POST /api/task`）且成功建立**新任務**時，會自動發送 FCM 推播通知到該站點的 Topic（`/topics/{stationCode}`）。

| 項目 | 說明 |
|------|------|
| **觸發時機** | 民眾回報溢滿，成功建立新任務（非重複回報） |
| **Topic** | `/topics/can_{stationCode}`（例如 `/topics/can_A12`） |
| **FCM Server Key** | 從 `src/app/fcm/fcm.config.ts` 讀取 |
| **未設定 Key** | 優雅跳過，不影響業務邏輯，僅記錄警告 |
| **失敗處理** | Fire-and-forget 模式，發送失敗不影響主流程 |

### 啟用 FCM 推播

編輯 `src/app/fcm/fcm.config.ts`，將 `serverKey` 填入從 Firebase 專案取得的 Server Key：

```typescript
export const FCM_CONFIG = {
    serverKey: 'AAAA...your-server-key...',
    fcmUrl: 'https://fcm.googleapis.com/fcm/send',
};
```

> 若 `serverKey` 留空，FCM 推播會被跳過，系統仍正常運作。

### FCM Payload 格式

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

| 資料欄位 | 說明 |
|----------|------|
| `data.system` | 固定為 `"can"`，App 用來區分系統 |
| `data.station_code` | 站點代碼 |
| `data.serial_number` | 任務序號（`serialNumber`） |
| `data.location` | 垃圾桶位置名稱 |
| `data.is_full` | 溢滿狀態（`"true"`） |

---

## 認證 (Auth)

| 方法 | 路由 | 認證 | 說明 |
|------|------|------|------|
| `POST` | `/api/auth/login` | 不需要 | 登入，取得 `access_token` |
| `GET` | `/api/auth` | 需要 | 驗證 token 有效性 |

### 登入 Request

```json
{
  "account": "string",
  "password": "string"
}
```

### 登入 Response

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs..."
}
```

> JWT Payload: `{ sub: "account", username: "account" }`

---

## 站點 (Station)

| 方法 | 路由 | 認證 | 說明 |
|------|------|------|------|
| `POST` | `/api/station?withDefaultAccount=true` | 需要 | 建立站點，可選擇同時建立預設帳號 |
| `GET` | `/api/station` | 需要 | 列出所有站點（排除根站點 `-`） |
| `GET` | `/api/station/:stationCode` | 需要 | 取得單一站點 |
| `PATCH` | `/api/station/:stationCode` | 需要 | 更新站點 |

### 建立/更新站點 Request

```json
{
  "stationCode": "A1",
  "name": "台北車站",
  "description": "說明",
  "lineNotifyToken": "",
  "synologyChatToken": "xxx"
}
```

> 建立時 `stationCode` 必填；更新時不需要。

---

## 帳號 (Account)

| 方法 | 路由 | 認證 | 說明 |
|------|------|------|------|
| `POST` | `/api/account` | 不需要 | 建立帳號 |
| `GET` | `/api/account` | 需要 | 列出所有帳號（不回傳密碼） |
| `GET` | `/api/account/:account` | 需要 | 取得單一帳號 |
| `PATCH` | `/api/account/:account` | 需要 | 更新帳號 |
| `PATCH` | `/api/account/password/:account` | 需要 | 變更密碼 |
| `PATCH` | `/api/account/disable/:account` | 需要 | 停用帳號 |
| `DELETE` | `/api/account/:account` | 需要 | 刪除帳號 |

### 建立帳號 Request

```json
{
  "station": "A1",
  "account": "user001",
  "fullName": "張三",
  "password": "password123",
  "ext": "1234",
  "phone": "0912345678",
  "email": "user@example.com",
  "description": "說明文字"
}
```

### 更新帳號 Request

```json
{
  "station": "A1",
  "fullName": "張三",
  "ext": "1234",
  "phone": "0912345678",
  "email": "user@example.com",
  "description": "說明文字"
}
```

### 變更密碼 Request

```json
{
  "password": "newPassword123"
}
```

---

## 垃圾桶 (Trash Bin)

| 方法 | 路由 | 認證 | 說明 |
|------|------|------|------|
| `POST` | `/api/trash-bin` | 需要 | 建立垃圾桶（會自動產生 QR Code） |
| `GET` | `/api/trash-bin` | 需要 | 列出所有垃圾桶 |
| `GET` | `/api/trash-bin/:code` | 不需要 | 取得單一垃圾桶（公開） |
| `GET` | `/api/trash-bin/station/:stationCode` | 需要 | 依站點列出垃圾桶 |
| `PATCH` | `/api/trash-bin/full-state/:code` | 需要 | 切換滿溢狀態 |
| `PATCH` | `/api/trash-bin/disable/:code` | 需要 | 停用垃圾桶 |
| `PATCH` | `/api/trash-bin/:code` | 需要 | 更新垃圾桶（會重新產生 QR Code） |
| `DELETE` | `/api/trash-bin/:code` | 需要 | 刪除垃圾桶（含相關任務與 QR Code） |

### 建立垃圾桶 Request

```json
{
  "station": "A1",
  "trashBinCode": "A1-B1-M1-1",
  "locationName": "女廁廁間2",
  "type": "toilet"
}
```

### 更新垃圾桶 Request

```json
{
  "locationName": "女廁廁間2",
  "type": "toilet"
}
```

### 更新滿溢狀態 Request

```json
{
  "isFull": true
}
```

---

## 任務 (Task) - 溢滿回報

| 方法 | 路由 | 認證 | 說明 |
|------|------|------|------|
| `POST` | `/api/task` | 不需要 | 民眾回報溢滿（公開；會記錄 IP/UA） |
| `POST` | `/api/task/abuse/:serialNumber` | 需要 | 回報濫用/假回報 |
| `GET` | `/api/task` | 需要 | 列出所有任務（未完成的優先） |
| `GET` | `/api/task/station/:stationCode?includeSystemClosed=false` | 需要 | 依站點列出任務 |
| `PATCH` | `/api/task/:serialNumber` | 需要 | 標記完成/未完成；清除滿溢狀態；停止推播 |
| `DELETE` | `/api/task/:serialNumber` | 需要 | 刪除任務 |

### 建立任務 Request（民眾回報）

```json
{
  "station": "A1",
  "trashBin": "A1-B1-M1-1",
  "visitorId": "abc123"
}
```

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `station` | `string` | 是 | 站點代碼 |
| `trashBin` | `string` | 是 | 垃圾桶代碼 |
| `visitorId` | `string` | 否 | 訪客裝置指紋（支援 `visitorId` / `visitorID` / `visitor_id`） |

### 回報濫用 Request

```json
{
  "station": "A1",
  "trashBin": "A1-B1-M1-1"
}
```

### 任務列表 Response

```json
[
  {
    "serialNumber": 1,
    "station": "A1",
    "trashBin": "A1-B1-M1-1",
    "isDone": false,
    "cleanAt": null,
    "informTime": 1,
    "resolutionType": 0,
    "visitorID": "abc123",
    "isDisable": false,
    "createdAt": "2024-01-15T08:30:00.000Z",
    "updatedAt": "2024-01-15T08:30:00.000Z"
  }
]
```

### 任務欄位說明

| 欄位 | 型別 | 說明 |
|------|------|------|
| `serialNumber` | `number` | 任務序號（主鍵） |
| `station` | `string` | 站點代碼 |
| `trashBin` | `string` | 垃圾桶代碼 |
| `isDone` | `boolean` | 是否已完成 |
| `cleanAt` | `Date \| null` | 清理時間 |
| `informTime` | `number` | 通知次數 |
| `resolutionType` | `number` | 結案類型：`0` 待處理, `1` 已完成, `2` 無問題, `3` 系統自動結案, `4` 黑名單自動結案 |
| `visitorID` | `string \| null` | 訪客裝置指紋 |
| `isDisable` | `boolean` | 是否停用 |
| `createdAt` | `Date` | 建立時間 |
| `updatedAt` | `Date` | 更新時間 |

### 任務完成 Request

```json
{
  "isDone": true,
  "resolutionType": 1
}
```

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `isDone` | `boolean` | 是 | `true` 標記完成，`false` 標記未完成 |
| `resolutionType` | `number` | 否 | `0` 待處理, `1` 已完成, `2` 無問題, `3` 系統自動結案, `4` 黑名單自動結案 |

> 當 `isDone` 為 `true` 時，`cleanAt` 會自動設為當前時間。

---

## 月報表 (Monthly Report)

| 方法 | 路由 | 認證 | 說明 |
|------|------|------|------|
| `POST` | `/api/monthly-report` | 不需要 | 手動建立月報表 |
| `GET` | `/api/monthly-report` | 需要 | 列出所有月報表 |

> **注意**：另有定時排程 `0 0 0 1 * *`（每月 1 號 00:00），自動彙整上月任務並產生報表。

### 建立月報表 Request

```json
{
  "year": 2024,
  "month": 1,
  "allTask": "[...]",
  "taskNumber": 100,
  "informTime": 150
}
```

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `year` | `number` | 是 | 年份 |
| `month` | `number` | 是 | 月份 |
| `allTask` | `string` | 是 | 任務 JSON 字串 |
| `taskNumber` | `number` | 是 | 任務總數 |
| `informTime` | `number` | 是 | 通知次數總計 |

---

## QR Code

| 方法 | 路由 | 認證 | 說明 |
|------|------|------|------|
| `GET` | `/api/qrcode?url=&code=&locationName=` | 不需要 | 產生 QR Code 圖片（回傳 HTML `<img>`） |
| `POST` | `/api/qrcode/all` | 需要 | 重新產生所有垃圾桶 QR Code |

### 產生 QR Code Request

Query Parameters:

| 參數 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `url` | `string` | 是 | QR Code 目標 URL |
| `code` | `string` | 是 | 垃圾桶代碼 |
| `locationName` | `string` | 是 | 位置名稱 |

### 重新產生所有 QR Code Request

```json
{
  "url": "https://www.tymetro.com.tw/can"
}
```

---

## Line Bot / Synology Chat

| 方法 | 路由 | 認證 | 說明 |
|------|------|------|------|
| `GET` | `/api/line-bot?station=&code=&location=&isFirst=&token=` | 不需要 | 推播 Synology Chat 訊息 |
| `POST` | `/api/line-bot/testing/:stationCode` | 不需要 | 發送測試訊息到指定站點 |
| `POST` | `/api/line-bot/webhook` | 不需要 | 接收 Webhook 事件（記錄群組 ID） |

### 推播 Synology Chat Request

Query Parameters:

| 參數 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `station` | `string` | 是 | 站點代碼 |
| `code` | `string` | 是 | 垃圾桶代碼 |
| `location` | `string` | 是 | 位置名稱 |
| `isFirst` | `boolean` | 是 | 是否首次推播 |
| `token` | `string` | 是 | Synology Chat Token |

---

## 認證說明

- **認證欄位**：「需要」表示需要 JWT Bearer Token（或 Super Token）
- **公開端點**：
  - `/api/task`（民眾回報）
  - `/api/trash-bin/:code`（查詢垃圾桶）
  - `/api/qrcode`（產生 QR Code）
- 所有 `PATCH` / `POST` 請求，根據 DTO 會進行 `ValidationPipe` 驗證

## 資料型別參考

### 垃圾桶類型 (TrashBinTypeEnum)

| 值 | 說明 |
|----|------|
| `nursery` | 育嬰室 |
| `publish` | 公共區 |
| `toilet` | 廁所 |
| `carriage` | 車廂 |

### 結案類型 (ResolutionType)

| 值 | 說明 |
|----|------|
| `0` | 待處理 (Pending) |
| `1` | 已完成 (Completed) |
| `2` | 無問題 (No Issue) |
| `3` | 系統自動結案 (System Rejected / Closed Hours) |
| `4` | 黑名單自動結案 (Blacklisted Auto Closed) |
