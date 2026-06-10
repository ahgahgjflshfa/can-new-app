# 站務系統桌面版需求說明

## 背景與目的

站務系統目前僅提供手機版 App，供站務人員在移動中處理任務。然而部分站點的站務人員有固定辦公座位，需要長時間盯螢幕處理多項業務，手機版在桌面使用情境下存在以下痛點：

- **螢幕太小**：手機畫面在桌面環境下顯示資訊量不足，操作不便
- **推播依賴**：手機版仰賴 Firebase 推播通知，桌面作業系統（macOS / Windows / Linux）無原生 FCM 支援，無法主動提醒新任務
- **多工切換**：手機版為單一畫面，桌面版可善用寬螢幕同時呈現更多資訊

因此規劃推出桌面版，讓站務人員可選擇最適合的裝置處理業務。

---

## 需求範圍

### 功能一致性

桌面版需與手機版提供**完全一致的核心功能**：

| 功能 | 說明 |
|------|------|
| 雙系統入口 | 統一系統選擇畫面，可進入「立碼幫幫忙」或「Q 潔淨立馬清」 |
| 登入認證 | 使用各自後端的 JWT Bearer Token 認證 |
| 任務列表 | 顯示所屬站點的任務，最多 20 筆 |
| 任務處理 | 立碼幫幫忙：回覆 / 結案；CAN：標記完成 |
| 設定頁面 | 帳號資訊、登出、進階設定（App 資訊、開發工具） |
| Session 隔離 | 兩套系統可同時保持登入，切換不需重新輸入帳密 |

### 平台支援

支援以下桌面作業系統：

- **macOS**
- **Windows**（Windows 10 及以上）
- **Linux**（需具備 libsecret 支援）

---

## 與手機版的主要差異

### 1. 推播改為定時輪詢

手機版透過 Firebase Cloud Messaging（FCM）接收後端主動推送的新任務通知。桌面版因技術限制（Firebase Messaging 無原生 macOS/Windows/Linux 實作），改以**定時輪詢**方式取得最新任務：

| 項目 | 手機版 | 桌面版 |
|------|--------|--------|
| 通知機制 | Firebase Push | Timer 輪詢（每 60 秒查詢一次 API） |
| 觸發時機 | 後端主動推送 | 畫面開啟時、手動下拉、Timer 觸發 |
| 後端負擔 | 低（被動接收） | 中等（主動查詢） |

> **注意**：輪詢僅在使用者進入任務列表且畫面可見時執行，切換至其他畫面或最小化時會停止，避免無謂的 API 呼叫。

### 2. 螢幕尺寸適配

桌面版螢幕寬度較大，UI 佈局會調整為更適合桌面的呈現方式（例如：寬版卡片、雙欄排列），但**業務流程與操作邏輯與手機版完全相同**。

---

## API 說明

桌面版與手機版**共用完全相同的後端 API**，不會因為是桌面版而新增或改變 API 端點。

### 立碼幫幫忙 API

| 方法 | 端點 | 說明 |
|------|------|------|
| `POST` | `/auth/login` | 登入，回傳 JWT token |
| `POST` | `/auth/logout` | 登出 |
| `GET` | `/tasks` | 取得任務列表 |
| `POST` | `/tasks/{id}/reply` | 回覆任務 |
| `POST` | `/tasks/{id}/complete` | 結案任務 |

**Base URL：** `https://www-u.tymetro.com.tw/station_services/api`

### Q 潔淨立馬清（CAN）API

| 方法 | 端點 | 說明 |
|------|------|------|
| `POST` | `/api/auth/login` | 登入，回傳 JWT token |
| `GET` | `/api/account/{account}` | 取得使用者所屬站點 |
| `GET` | `/api/task/station/{stationCode}` | 依站點取得任務列表 |
| `PATCH` | `/api/task/{serialNumber}` | 標記完成/未完成 |

**Base URL：** `https://www.tymetro.com.tw/can_api/api`

### 認證方式

兩套系統均使用 **JWT Bearer Token**，於 HTTP Header 中傳送：

```
Authorization: Bearer <token>
```

---

## 已知問題與風險

### 1. 無法主動推播通知（重要）

桌面版**無法像手機版一樣在背景接收推播通知**。這表示：
- 站務人員必須保持 App 開啟並在任務列表畫面，才能透過輪詢得知新任務
- 若 App 被最小化或切換至其他應用程式，將不會自動提醒新任務
- **建議**：桌面版使用場景應以「常駐開啟的螢幕」為主，而非離線等待通知

### 2. 輪詢對後端的額外負擔

每 60 秒查詢一次 API，若大量站務人員同時使用桌面版，可能對後端造成比手機版更高的 QPS（每秒查詢數）。

**風險等級**：中  
**因應措施**：輪詢僅在畫面可見時執行，且單一使用者僅輪詢當前所在的系統（不會同時輪詢立碼幫幫忙和 CAN）。

### 3. Session 儲存的平台差異

桌面版使用 `flutter_secure_storage` 儲存登入 session，各平台實作不同：

| 平台 | 儲存機制 |
|------|----------|
| macOS | Keychain |
| Windows | DPAPI（Data Protection API）|
| Linux | Secret Service API（libsecret）|

**潛在問題**：
- **Linux**：部分發行版預設未安裝 `libsecret`，需手動安裝 `libsecret-1-dev`，否則 Session 無法持久化
- **Windows**：不支援 Windows 7，僅 Windows 10 及以上版本可正常使用
- **macOS**：需使用者首次執行時授權 Keychain 存取

### 4. 兩系統無法同時顯示（與手機版相同限制）

與手機版一樣，必須切換系統才能查看另一套任務，無法在同一畫面同時監控立碼幫幫忙和 CAN 的任務狀態。

### 5. CAN 後端已整合 FCM 推播（僅影響手機版）

CAN 後端已於 `POST /api/task`（民眾回報溢滿建立新任務）時自動發送 FCM 推播。此功能與桌面版無直接關聯，因為桌面版本來就不使用推播，仍將繼續使用輪詢機制。

---

## 驗證方式

```bash
# macOS 本地執行
flutter run -d macos

# 靜態分析
flutter analyze

# 執行測試
flutter test

# 建置 macOS 桌面應用程式
flutter build macos

# 建置 Windows 桌面應用程式（需於 Windows 環境）
flutter build windows

# 建置 Linux 桌面應用程式（需於 Linux 環境）
flutter build linux
```

---

## 相關文件

- `AGENTS.md`：手機版架構設計
- `AGENTS_DESKTOP.md`：桌面版技術架構設計（含程式碼層級說明）
- `API.md`：CAN 後端 API 完整清單
- `FCM_INTEGRATION_MEMO.md`：後端整合 Firebase Push 指南
