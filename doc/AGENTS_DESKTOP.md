# 站務系統桌面版架構設計

## 專案概述

桌面版為站務系統 App 的跨平台延伸，讓站務人員可在 **macOS / Windows / Linux** 桌面上執行相同的業務流程：登入、查看任務、回覆與結案。

與手機版共享 90% 以上的業務邏輯與 UI 元件，核心差異僅在「**推播機制改為輪詢**」與「**螢幕尺寸適配**」。

---

## 核心架構原則

### 1. 單一程式碼庫，平台自適應

同一套 Flutter 程式碼透過條件編譯與平台檢測，在桌面端與手機端執行相同的功能。

```dart
// 平台檢測範例
import 'dart:io';

bool get isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

bool get isMobile => Platform.isAndroid || Platform.isIOS;
```

### 2. 推播改為輪詢

桌面端 **不使用 Firebase Cloud Messaging**（`firebase_messaging` 無原生 macOS/Windows/Linux 實作），改以 **Timer 定時輪詢**後端 API 取得最新任務。

| 機制 | 手機版 | 桌面版 |
|------|--------|--------|
| 新任務通知 | Firebase Push + 手動下拉 | Timer 輪詢（每 60 秒）+ 手動下拉 |
| 任務列表刷新 | `PushNotificationService.refreshSignal` | `PollingService.refreshSignal` |
| 後端負擔 | 低（被動接收） | 中（主動查詢） |

### 3. 雙系統 Session 共用儲存機制

桌面版沿用 `flutter_secure_storage`：

- **macOS**：Keychain
- **Windows**：DPAPI（Data Protection API）
- **Linux**：Secret Service API（`libsecret`）

Session key 與手機版完全相同：

```
limabang.token      / can.token
limabang.user_json  / can.user_json
limabang.device_id  / can.device_id
```

---

## 與手機版的核心差異

### 差異 1：無 Firebase 初始化

桌面端呼叫 `Firebase.initializeApp()` 會擲出例外（無可用實作），需優雅降級：

```dart
// main.dart 調整
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final pushService = PollingService(); // 桌面版統一使用 PollingService
  if (isMobile) {
    await pushService.initializeFirebase(); // 僅手機端初始化 FCM
  }
  
  // ...其餘與手機版相同
}
```

### 差異 2：PollingService 取代 PushNotificationService

桌面端不建立 `PushNotificationService`，改注入 `PollingService`（兩者均實作相同的 `RefreshSignal` 介面）。

```dart
abstract class RefreshService {
  ValueNotifier<int> get refreshSignal;
  void start();
  void stop();
}
```

`PollingService` 內部使用 `Timer.periodic`：

```dart
class PollingService implements RefreshService {
  final ValueNotifier<int> refreshSignal = ValueNotifier(0);
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      refreshSignal.value += 1;
      AppLogger.log('Polling', 'triggered refresh');
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
```

### 差異 3：Timer 僅在畫面可見時觸發

避免桌面版在背景無謂消耗後端資源：

```dart
class _TasksScreenState extends State<TasksScreen>
    with WidgetsBindingObserver {
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.refreshService.start();
    } else {
      widget.refreshService.stop();
    }
  }
}
```

### 差異 4：UI 寬螢幕適配

桌面版螢幕寬度遠大於手機，任務列表改為 **左右雙欄** 或 **擴展卡片寬度**：

| 畫面 | 手機版 | 桌面版 |
|------|--------|--------|
| 系統選擇 | 單欄垂直排列 | 雙欄並排 |
| 任務列表 | 單欄卡片 | 雙欄網格或寬版卡片 |
| 設定頁面 | 單欄滿寬 | 置中限制寬度（maxWidth: 720） |

建議使用 `LayoutBuilder` 或 `MediaQuery` 判斷寬度：

```dart
bool get isWideScreen => MediaQuery.of(context).size.width > 900;
```

### 差異 5：Device Type 調整

登入 API 的 `deviceType` 欄位在桌面端回報為 `desktop`：

```dart
// login_screen.dart / can_login_screen.dart
String get deviceType {
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  return 'desktop'; // macOS / Windows / Linux 統一
}
```

---

## 輪詢機制詳細設計

### 輪詢頻率

| 情境 | 頻率 | 說明 |
|------|------|------|
| 前台活躍 | 60 秒 | 正常使用時每分鐘更新一次 |
| 手動下拉 | 即時 | 使用者主動觸發 `RefreshIndicator` |
| 畫面開啟 | 即時 | 進入任務列表時立即 fetch |
| 背景/最小化 | 停止 | 不消耗後端資源 |

### 輪詢對象

桌面版僅輪詢「當前已登入且畫面可見」的系統：

- 若使用者在 **立碼幫幫忙** 任務列表 → 僅輪詢 `limabangApi.fetchTasks()`
- 若使用者在 **CAN 任務列表** → 僅輪詢 `canApi.fetchTasksByStation()`
- 若使用者在 **系統選擇畫面** → 停止所有輪詢

### 錯誤處理

輪詢失敗時不彈出錯誤對話框，僅記錄日誌並保留既有資料：

```dart
try {
  final tasks = await widget.api.fetchTasks();
  setState(() => _tasks = tasks);
} on ApiException catch (e) {
  AppLogger.log('Polling', 'fetch failed: ${e.message}');
  // 不顯示錯誤 UI，保留既有任務列表
}
```

---

## 資料流

### 登入流程

與手機版相同：

```
[系統選擇] → [登入畫面] → [POST /auth/login] → [GET /account/{account}] → [儲存 session] → [任務列表]
```

桌面版登入後 **不訂閱 push topic**（無 FCM）。

### 任務列表刷新（桌面版）

```
[畫面初始化] → [載入 session] → [fetchTasksByStation(station)] → [渲染列表]
                    ↑                                  ↑
            [每 60 秒 Timer 觸發]          [手動下拉 / 畫面重新可見]
```

### 登出流程

與手機版相同：

```
[設定頁面] → [呼叫 logout API] → [清除 SecureStorage] → [返回系統選擇]
```

登出時同時停止輪詢 Timer。

---

## 目錄結構調整

僅新增/調整與平台差異相關的檔案，業務邏輯完全復用：

```
lib/
├── main.dart                          # 平台檢測，決定注入 PushService 或 PollingService
├── app.dart                           # 無變更
│
├── services/
│   ├── refresh_service.dart            # ★ 新增：RefreshService 抽象介面
│   ├── push_notification_service.dart # 僅手機端使用
│   ├── polling_service.dart           # ★ 新增：桌面端輪詢實作
│   ├── limabang_api.dart              # 無變更
│   ├── limabang_api_client.dart       # 無變更
│   ├── can_api.dart                   # 無變更
│   ├── can_api_client.dart            # 無變更
│   ├── session_store.dart             # 無變更（桌面端已支援）
│   ├── api_log_store.dart             # 無變更
│   └── app_logger.dart                # 無變更
│
├── screens/
│   ├── system_selection_screen.dart   # 適配寬螢幕佈局
│   ├── login_screen.dart              # deviceType 回報邏輯調整
│   ├── can_login_screen.dart          # deviceType 回報邏輯調整
│   ├── tasks_screen.dart              # 注入 RefreshService，生命週期管理
│   ├── can_tasks_screen.dart          # 注入 RefreshService，生命週期管理
│   ├── settings_screen.dart           # 隱藏推播相關資訊（桌面版無推播）
│   └── can_settings_screen.dart       # 隱藏推播相關資訊（桌面版無推播）
│
├── widgets/                           # 無變更
├── theme/                             # 無變更
└── utils/
    └── platform_helper.dart           # ★ 新增：isDesktop / isMobile / deviceType 統一判斷
```

---

## 技術實作要點

### 1. pubspec.yaml 無需變更

`flutter_secure_storage` 已內建支援 macOS/Windows/Linux，無需新增依賴。

`firebase_messaging` 雖然無桌面端實作，但不會導致編譯失敗（僅在執行期擲出例外），可保留在手機版使用。

### 2. main.dart 注入邏輯

```dart
import 'dart:io';
import 'services/polling_service.dart';
import 'services/push_notification_service.dart';

bool get _isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final limabangApi = LimabangApiClient();
  final canApi = CanApiClient();
  final sessionStore = SecureSessionStore();
  // ...session 載入與手機版相同
  
  final refreshService = _isDesktop
      ? PollingService()
      : PushNotificationService();
      
  if (!_isDesktop) {
    await (refreshService as PushNotificationService).initialize();
  }
  
  runApp(MyApp(
    limabangApi: limabangApi,
    canApi: canApi,
    refreshService: refreshService, // 統一注入 RefreshService
    sessionStore: sessionStore,
    // ...
  ));
}
```

### 3. 畫面生命週期管理

`TasksScreen` 與 `CanTasksScreen` 不再直接依賴 `PushNotificationService`，改依賴抽象的 `RefreshService`：

```dart
class TasksScreen extends StatefulWidget {
  const TasksScreen({
    required this.api,
    required this.user,
    required this.refreshService, // ★ 改為 RefreshService
    required this.sessionStore,
    super.key,
  });

  final LimabangApi api;
  final UserProfile user;
  final RefreshService refreshService; // 可能是 PollingService 或 PushNotificationService
  final SessionStore sessionStore;
}
```

### 4. 設定頁面推播狀態顯示

桌面版的「進階設定」中，推播狀態區塊顯示為「桌面版不適用」或隱藏：

```dart
Widget _buildPushStateSection(PushNotificationState? pushState) {
  if (pushState == null) {
    return _SettingsSection(
      title: '推播狀態',
      children: [
        _InfoTile(label: '通知機制', value: '桌面版輪詢（每 60 秒）'),
      ],
    );
  }
  // ...手機版原有邏輯
}
```

---

## 安全性

| 項目 | 桌面版措施 |
|------|-----------|
| Session 儲存 | `flutter_secure_storage`（macOS Keychain / Windows DPAPI / Linux Secret Service） |
| Token 傳輸 | `Authorization: Bearer <token>` header |
| 日誌脫敏 | 密碼與 Bearer Token 不打印 |
| Debug 匯出 | 敏感資訊僅在「一鍵分享 Debug」中可見 |

---

## 已知限制

1. **無推播通知**：桌面版無法像手機版一樣在背景接收 Firebase Push，必須保持 App 開啟才能透過輪詢取得新任務
2. **輪詢頻率上限**：若同時開啟雙系統任務列表，後端 QPS 會倍增（建議在「進階設定」提供輪詩頻率調整）
3. **Linux 需 libsecret**：部分 Linux 發行版需手動安裝 `libsecret-1-dev` 才能使用 `flutter_secure_storage`
4. **Windows 7 不支援**：`flutter_secure_storage` 的 Windows 實作僅支援 Windows 10+

---

## 驗證指令

```bash
# macOS
flutter run -d macos

# Windows（需在 Windows 環境）
flutter run -d windows

# Linux（需在 Linux 環境）
flutter run -d linux

# 靜態分析
flutter analyze

# 測試
flutter test
```

---

## 相關文件

- `AGENTS.md`：手機版架構設計
- `API.md`：CAN 後端 API 完整清單
- `FCM_INTEGRATION_MEMO.md`：後端整合 Firebase Push 指南（僅手機版適用）
