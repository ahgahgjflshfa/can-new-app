# 站務系統 App 架構設計 (AGENTS)

## 專案概述

本專案為桃園捷運站務人員使用的 Flutter App，整合兩套獨立系統：

- **立碼幫幫忙**（Limabang）：無障礙求助系統
- **Q 潔淨立馬清**（CAN）：垃圾桶溢滿回報系統

兩套系統使用獨立後端與資料庫，透過統一的 Flutter App 提供一致的使用者體驗。

---

## 核心架構原則

### 1. 雙系統並行，不整合後端

| 系統 | 後端 | 認證 | 資料庫 |
|------|------|------|--------|
| 立碼幫幫忙 | `https://www-u.tymetro.com.tw/station_services/api` | JWT Bearer Token | 獨立 |
| Q 潔淨立馬清 | `https://www.tymetro.com.tw/can_api/api` | JWT Bearer Token | 獨立 |

**決策原因**：兩套系統由不同團隊維護，整合後端風險高、時程長。App 層整合可快速上線，且對後端零侵入。

### 2. 統一入口：系統選擇畫面

App 啟動後一律進入 `SystemSelectionScreen`，不會自動進入上次使用的系統。

**決策原因**：
- 避免使用者從 Task 列表按返回鍵時看到黑畫面
- 明確讓使用者選擇當下要處理的業務系統
- 兩套系統的 session 獨立檢查，載入速度不互相影響

### 3. 雙 Session 隔離儲存

使用 `flutter_secure_storage`，以不同 key prefix 隔離：

```
limabang.token      / can.token
limabang.user_json  / can.user_json
limabang.device_id  / can.device_id
```

兩系統可同時保持登入狀態，切換系統不需重新輸入帳密。

---

## 目錄結構

```
lib/
├── main.dart                          # App 進入點，初始化 Firebase
├── app.dart                           # MaterialApp + 主題設定
│
├── models/                            # 資料模型（兩套系統獨立）
│   ├── app_session.dart               # 立碼幫幫忙 session
│   ├── can_session.dart               # CAN session
│   ├── user_profile.dart              # 立碼幫幫忙使用者
│   ├── can_user_profile.dart          # CAN 使用者（欄位不同）
│   ├── assist_task.dart               # 立碼幫幫忙任務
│   ├── can_task.dart                  # CAN 溢滿任務
│   └── ...                            # 其他 enum / 輔助模型
│
├── services/                          # 核心服務層
│   ├── limabang_api.dart              # 立碼幫幫忙 API contract (abstract)
│   ├── limabang_api_client.dart       # 立碼幫幫忙 API 實作
│   ├── can_api.dart                   # CAN API contract (abstract)
│   ├── can_api_client.dart            # CAN API 實作
│   ├── push_notification_service.dart # 共享 Firebase Push
│   ├── session_store.dart             # SecureStorage 封裝
│   ├── api_log_store.dart             # API 呼叫紀錄
│   └── app_logger.dart                # 應用程式日誌
│
├── screens/                           # 全頁面流程
│   ├── system_selection_screen.dart   # 系統選擇（App 入口）
│   ├── login_screen.dart              # 立碼幫幫忙登入
│   ├── can_login_screen.dart          # CAN 登入
│   ├── tasks_screen.dart              # 立碼幫幫忙任務列表
│   ├── can_tasks_screen.dart          # CAN 溢滿任務列表
│   ├── settings_screen.dart           # 立碼幫幫忙設定
│   ├── can_settings_screen.dart       # CAN 設定
│   └── ...
│
├── widgets/                           # 可複用元件
│   ├── error_state.dart
│   ├── snack_bar_message.dart
│   └── ...
│
└── theme/
    └── app_colors.dart                # 統一色彩規範
```

---

## 關鍵設計決策

### 決策 1：統一任務列表標題

兩套系統的任務列表 AppBar 標題皆為「**任務列表**」，不顯示「溢滿任務列表」等區分文字。

**原因**：統一視覺語言，降低使用者認知負擔。系統差異由顏色主題（立碼=藍色、CAN=綠色）與內容欄位隱性區分。

### 決策 2：設定頁面簡化設計

| 畫面 | 內容 |
|------|------|
| 設定主頁 | 僅顯示「帳號資訊」與「登出」 |
| 進階設定（AppBar 按鈕進入） | App 資訊、推播狀態、開發工具（API 紀錄、推播紀錄、App Logs） |

**原因**：
- 一般使用者只需看到帳號與登出
- Base URL、Device ID、Token 等敏感資訊不直接顯示
- Debug 資訊透過「一鍵分享 Debug 資訊」按鈕匯出，而非逐欄展示

### 決策 3：`_send` 回傳 `Object?`

CAN API 的登入回傳 `Map<String, dynamic>`（物件），任務列表回傳 `List<dynamic>`（陣列）。

```dart
Future<Object?> _send(...)  // 回傳 Map 或 List
```

**原因**：在不改變後端的前提下，用單一方法處理不一致的 JSON root 型別。

### 決策 4：Boolean 解析相容層

CAN 後端部分欄位（`isDone`, `isDisable`）傳送 `int`（0/1），部分傳送 `bool`。

```dart
static bool _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  return false;
}
```

**原因**：後端歷史欄位型別不一致，App 層提供防禦性解析。

### 決策 5：站點綁定任務查詢

CAN 登入回傳直接包含 `account`、`station`、`topic`，無需額外呼叫 `GET /account/{account}`。後續任務查詢使用 `GET /task/station/{stationCode}`。

**原因**：
- 後端簡化登入流程，一次回傳所有必要資訊
- 確保使用者只看到所屬站點的任務
- 限制最多顯示 20 筆（`List.take(20)`）

### 決策 6：共享 Firebase Push

兩套系統共用同一個 Firebase 專案與 `PushNotificationService` 實例。

```dart
// 登入時訂閱站點 topic
pushService.subscribeToTopic(user.station!)
```

**原因**：
- 裝置只需一個 FCM Token
- 後端各自獨立發送推播（CAN 後端需額外整合 FCM，參考 `FCM_INTEGRATION_MEMO.md`）

---

## 資料流

### 登入流程

```
[系統選擇] → [登入畫面] → [POST /auth/login] → [儲存 session] → [訂閱 push topic] → [任務列表]
```

### 任務列表刷新

```
[畫面初始化] → [載入 session] → [fetchTasksByStation(station)] → [渲染列表]
                    ↑
            [Push 通知觸發 refreshSignal]
```

### 登出流程

```
[設定頁面] → [呼叫 logout API] → [清除 SecureStorage] → [取消 push topic] → [返回系統選擇]
```

---

## 安全性

| 項目 | 措施 |
|------|------|
| Session 儲存 | `flutter_secure_storage`（加密） |
| Token 傳輸 | `Authorization: Bearer <token>` header |
| 日誌脫敏 | 密碼與 Bearer Token 不打印 |
| Debug 匯出 | 敏感資訊僅在「一鍵分享 Debug」中可見，不直接顯示於 UI |

---

## 已知限制

1. **~~CAN 後端尚未整合 FCM~~ → 已整合**：CAN 後端已於 `POST /api/task`（民眾回報溢滿建立新任務）時自動發送 FCM 推播到 `/topics/can_{stationCode}`。詳見 `API.md` FCM 推播整合章節與 `FCM_INTEGRATION_MEMO.md`。
2. **兩系統無法同時顯示**：必須切換系統才能查看另一套任務
3. **iOS/macOS 建置需完整 Xcode**：Android 開發不受影響

---

## 驗證指令

```bash
# 靜態分析
flutter analyze

# 測試
flutter test

# 建置
flutter build apk --debug
```

---

## 相關文件

- `README.md`：專案基本說明與執行方式
- `API.md`：CAN 後端 API 完整清單
- `FCM_INTEGRATION_MEMO.md`：後端整合 Firebase Push 指南
