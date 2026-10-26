# Parcel Express（modId parcel_delivery）

Transport Fever 3 模組：新增貨物「包裹」。居民與商工業把包裹寄到投遞箱，箱型貨車經由配送點載走，送到住宅區。

## 開發流程

- 程式用 Teal（`.tl`）撰寫。型別檢查：`powershell -ExecutionPolicy Bypass -File tools\check.ps1`。執行前先把 `C:\Users\kurow\tools\tl\tl-0.24.7-windows-x86_64` 加進 PATH。
- 部署：`powershell -ExecutionPolicy Bypass -File tools\deploy.ps1`，預設部署到 `staging_area`。型別檢查通過才部署。
- 使用者說「希望部署發布版本」（或「部屬發布版本」）時，用 `tools\deploy.ps1 -Release`：部署出去的 `content\parcel_delivery\debug.tl` 會把 `Enabled` 改成 `false`，關閉診斷計算與一般 log，只留錯誤訊息與 perf 行；專案裡的檔案維持 `true`。平常測試用一般部署。
- 除錯開關 `pd_debug.Enabled`（`parcel_delivery/debug.tl`）：新增的診斷計算或一般 log 都要包在開關裡，一般 log 用遊戲腳本的 `info()`；錯誤訊息與 perf 行直接用 `log.message`。
- 效能量測：遊戲腳本每 60 秒遊戲時間寫一行 `[parcel_delivery] perf`（各部分次數／平均／最長毫秒、腳本佔現實時間的 `share`、道路段數與城鎮建築數等數量）。`tools\perf.ps1` 匯總目前的 log，`-Save <名稱>` 存到 `perf\<名稱>.csv`，`-Compare` 並列所有存檔。比較優化時用同一個存檔、同一個遊戲速度，各跑 5 分鐘以上。
- 同一個模組 ID 同時存在於 `staging_area` 和 `local\mods` 時，遊戲載入的是 staging 的版本。log 裡會出現 `modHubId=StagingArea,<modId>`。
- 遊戲 log：`C:\Program Files (x86)\Steam\userdata\84279570\3493540\local\crash_dump\stdout.txt`，用 `[parcel_delivery]` 篩選。
- 遊戲本體在 `D:\SteamLibrary\steamapps\common\Transport Fever 3`。型別定義在 `api\tealdef` 和 `base\tealdef`，原版腳本多半包在 `base\content\*.zip` 裡。
- 已移除的建築（`parcel_post`、`parcel_source`、`parcel_drop_warehouse`、`parcel_office`）保留建築檔，舊存檔才讀得起來。它們都從建造選單隱藏，前三種由遊戲腳本在讀檔時自動拆除。

## 目前的設計

- **包裹投遞箱**（`parcel_drop.con.lua`、`parcel_drop.script.tl`）
  - 用原版倉庫腳本生成，拿掉所有看得到的部分，換成郵筒模型。
  - 設定 `skipCollision`，不拆周圍建築。
  - 吸附道路，距離 0.5 m。
  - 帶一塊 3 × 3 m 的不可見地面佔地和碰撞框，站點才涵蓋得到它的庫存。
  - 包裹庫存帶無投入的生產規則，產量由遊戲腳本設定生產效率來控制。
- **配送點**（`parcel_box.con.lua`、`parcel_box_twosided.con.lua`）
  - 路邊站牌，屬於街道附屬物件，範圍 160 m，模型是三個紙箱。
  - 建造選單有單側版（`parcel_box.con.lua`，「包裹投遞處（單側）」）與雙側版（`parcel_box_twosided.con.lua`，「包裹投遞處（雙側）」）。單側版曾從選單移除，2026-10-25 放回。投遞箱擺在單側版站牌的那一側、雙側版道路的右側。
  - 裝卸設定只限 PARCEL 類。
- **遊戲腳本**（`content/parcel_delivery.script.tl`）
  - 範圍內的居民和商工業建築歸給最早蓋好的投遞箱。城鎮建築依城鎮分批掃描（`getTown2BuildingMap`）：每 2 秒一輪，每座城鎮每 15 輪（30 秒）輪到一次，各城鎮對每個投遞箱的份額存在狀態 `townShares`，投遞箱的居民與商工業是全部份額的加總。新投遞箱最多 30 秒後才算到居民。
  - 每 5 輪（10 秒）一次的工作各排在不同輪次（`ScanTurn`）：城鎮需求、找投遞箱、找包裹投遞處、分揀中心加速、除錯診斷，不擠在同一輪。
  - 每年產量 = 居民 × 0.5 × 倍率 ＋ 商工業消耗量 × 0.5 × 倍率。兩個倍率的選項都是 0.5／1／1.5／2，預設 1。
  - 換算成生產效率送給庫存，最低相當於每年 12 個（週期最長約一個月）。投遞箱增減時，下一輪重新掃描全部城鎮。生產規則卡在遠期週期的投遞箱（下一個包裹排在最低效率週期 3 倍以上之後）會被拆除，由配對流程重蓋。
  - 投遞處配對最近的投遞箱（12 m 內，同一位置時取最早蓋的）。12 m 內沒被任何投遞處配對的投遞箱是多的，直接拆除。2026-10-27 發現測試存檔 24 個投遞處各有 2 個疊在同一位置的投遞箱，推測是遊戲在兩個 Lua 狀態同時執行 update、對同一投遞處各送出一次建造。
  - 新的投遞箱若 12 m 內沒有道路就拆掉。配送點由玩家自己蓋。腳本自動加配送點的做法已放棄：建設提案檢查通過，送出後卻從沒建起來。
- **跨城包裹分揀中心**（`parcel_sorting.script.tl`、`parcel_sorting_export.con.lua`、`parcel_sorting_import.con.lua`）
  - 模型是原版貨物倉庫：腳本自己依序呼叫倉庫 `updateFn`、貨物模組 `modules.script@goods.updateFn`（第一個插槽）和倉庫的 `terminateConstructionHook`，因為建築沒有 `modules` 參數時，遊戲不會套用模組。結果只留 `subconstructions`、`snapPoint`，拿掉 `warehouse` 元件與存放庫存，沒有插槽，玩家不能加模組。貨物模組的庫存模型分給投入與產出庫存當 `loadIndicators`。相對路徑轉成 `::/warehouses/`。
  - 同一個庫存清單裡有投入庫存（0）與產出庫存（1），各 800，規則 `{{1}}` 一換一，每年 400 次。出口：包裹 → 包裹（長距離運輸）；進口反過來。
  - 工人：子建築帶 `personCapacity`（INDUSTRIAL 20 人，禁止步行與開車），原版 `industry_workers.gs` 會處理它。加速倍率由建築結果 `metadata.workersBoostFactor = 2.5` 指定（存成 `persistentMetadata`，2026-10-24 確認有讀到）；加速卡片顯示「倍率 − 1」，2.5 顯示為 +150%，每年 1000 個。遊戲腳本另外把大於 1 且不等於 2.5 的效率改回 2.5，防止讀不到時用到原版 1.5～2.5 的隨機倍率。
  - 視窗：`gui/parcel_delivery/sorting_eow.script.tl` 掛在空建築視窗，用原版元件組出生產（`ProductionRulesWidget`）、加速效果（`WorkplacesBoosterRow`＋`WorkersTable`）、投入與產出庫存（`CombinedStockGroupedCounts`）四張卡片。沒設 `isIndustry`，以免被產業的擴建與倒閉機制處理。
  - 新貨物 `cargos/parcel/parcel_intercity.cargo.lua`：類別 UNIVERSAL、GOODS，不含 PARCEL，投遞處不處理。分類 `parcel_intercity` 沒加進經濟設定，城鎮不需要它。價格和配送時間與包裹相同（`mod.script.tl` 一併改寫）。
  - 沒有自己的車站，靠周圍車站的範圍涵蓋庫存。遊戲腳本用 metadata `parcel_delivery_sorting` 找出分揀中心，每次摘要記錄庫存、轉換次數與涵蓋的車站數。
  - 建造選單：道路建築 → 貨運。圖示與預覽圖是模組內的 `parcel_sorting_{export,import}@2x.tga`（240 × 150）與 `parcel_sorting_{export,import}_preview@2x.tga`（720 × 405），起初複製自原版貨物倉庫的圖，讓使用者自行修改。
  - 跨城包裹圖示是 `cargos/parcel/parcel_export@2x.tga`（48 × 48）。遊戲用的 TGA 一律存成 32 位元、不壓縮；使用者給的 RLE 壓縮檔先轉換過。
- **住宅需求**：`content/mod.script.tl` 用 `loadEconomy` 加入「parcel」貨物分類，`townConsumptionFactor = 2.5 ×` 模組參數 `parcel_delivery_demand`（0.5／0.75／1／1.25／1.5，預設 1）（新存檔中係數 5.3 時需求約為人口的兩倍；2.7 時偶爾有城鎮需求高過人口，改成 2.5；舊存檔的需求數字不能拿來校正）。係數在開新遊戲時就固定在存檔裡，之後改係數只影響新遊戲；2026-10-24 確認：舊存檔仍是係數 2 的需求，新存檔正常。
- **包裹價格**：`cargos/parcel/parcel.cargo.lua` 用原版 `logisticDecayFn`，配送時間由模組參數 `parcel_delivery_time` 選：蔬菜 1125、穀物 1286（預設）、羊毛 1500、家具 1800 秒；`mod.script.tl` 用 `loadCargoType` 改寫時間，並把 `decayStart` 設為時間的一半、`decayRate` 設為 5 ÷ decayStart。原版貨物每公尺 3.8；包裹上下限為 1.2 倍與 0.8 倍，剩餘時間 50% 時 1.0 倍（decayMod 1，對稱曲線）。參數推導寫在檔頭註解。尚未在遊戲中確認收入函式的時間參數與 `timeToDeliverInSeconds` 是同一個時鐘（假設一天 2000 ms）。
- **介面**（`content/gui/parcel_delivery/`）
  - 投遞箱的倉庫視窗有包裹生產卡片。
  - 路線視窗有每站等待包裹數。
  - 空建築視窗拿掉鏡頭特寫。

## 已驗證的引擎行為

- **站點涵蓋需要地面佔地**：站點的貨物涵蓋範圍只包含有地面佔地（`groundFaces` 或 `colliders`）的建築庫存。是否接道路、是否有倉庫元件、是否 `skipCollision` 都無關。
- **街道附屬物件不能有庫存**：停靠站加了庫存會被忽略。不是停靠站的街道附屬物件，蓋不起來。
- **`makeStockSetCargoAmountCmd` 會重建庫存**：它會刪掉庫存裡所有貨物再重新建立，貨物原本的目的地也跟著消失。剛寫入就讀 `getStockCount`，會把新舊貨物一起算進去，看起來像數量翻倍。
- **生產規則的週期**：一次生產需要 `一年 ÷ capacity ÷ 生產效率`。生產效率用 `makeStockListSetModifiersCmd` 設定。**下一個產出的時間在上一個產出時就用當下效率排定，之後改效率不會重排**（2026-10-27 確認：效率 0.001 時排出的週期 14,610 秒，改回 3.0 後仍不產出，重建才恢復；`applyHistory` 的 `interval` 記錄週期）。所以效率不能壓得太低。**效率設成 0 等於除以零，規則會以最快速度生產。**
- **加了投入庫存的規則不會轉換**：模組自訂貨物當投入、規則 `{{1}}`，結果完全沒有轉換。那個貨物屬於 GOODS 類時，包裹和磚頭的卸貨速度出現 -25%。
- **自訂貨物類別無效**：模組自訂的類別（例如 PARCEL），站點判斷涵蓋時不認得。站牌只接受這個類別時，就涵蓋不到包裹庫存。
- **站點的月台設定**
  - 車站至少要有一個月台，否則放置時遊戲崩潰（assert `terminals.empty()`）。
  - 每個月台都要有帶貨物類別的 `cargoTransferSpeeds`，否則車站視窗在 `getCargoClassId` 出錯。
- **維修設施的限制**：維修容量 0 又沒有車道時，會被拒絕建造（`neither depot nor a maintenance station`）。服務對象設成 `PERSON` 時，遊戲崩潰。
- **人行道不能接到車道**：可連接的人行道終點落在可連接卡車車道的節點上時，遊戲崩潰（`person0 == person1`，IsValidTransition）。
- **建設提案的清單要整份指定**：`proposal.constructionsToAdd = { ce }` 才有效。寫成 `constructionsToAdd[1] = ce`，只改到一份複本，送出的提案是空的，遊戲不做事也不報錯。建築檔名用 `parcel_delivery::/parcel_delivery/x.con`，送出用 `makeWorldBuildProposalCmd(proposal, nil, true, false)`。道路提案的清單（`edgesToAdd` 等）應該也一樣，`comp.objects` 也要先取出成變數，改完再整份指定。
- **遊戲腳本的錯誤會讓生產停止**：update 拋出錯誤（log 有 `Error while running game script`）時，所有投遞箱的生產規則都不再產出（2026-10-27 觀察到：錯誤開始後 `applyHistory` 不再增加）。錯誤也會讓狀態沒有存回去，同一輪一直重跑。update 整個包在 `pcall` 裡，各部分也各自 `pcall`，出錯只寫 log。
- **遊戲腳本的限制**
  - `api.cmd.sendCommand` 不能附回呼函式（`Callbacks are currently disallowed`）。
  - `forEachEntityWithComponent` 不能用在 `STOCK_LIST`。
  - `streetSystem.getEdgeObject2EdgeMap()` 在遊戲腳本裡傳回空表。要找站牌這類街道附屬物件，改走 `getNode2StreetEdgeMap()`，再讀每段道路 `BASE_EDGE.objects` 的物件，取其 `EDGE_OBJECT` 元件。
- **建築腳本的路徑**：以 `util.useFn` 呼叫原版建築腳本時，結果裡的相對路徑會被解析到本模組。用之前要先轉成 `::/` 開頭的絕對路徑。
- **舊的模組預設組合會讓新遊戲崩潰**：預設組合存有已刪除的內容時，開始新遊戲會在 `map_util.h` 的 `Get` 出現 assert `it != map.end()`，log 前面有 `Loading preset: <名稱>`。這和模組程式無關，重新建立預設組合即可。
- **相關介面元件**：
  - 生產規則：`industry_react_util.ProductionRulesWidget`。
  - 庫存：`entity_window_util.CombinedStockGroupedCounts`。
  - 放置時畫範圍圈：只有車站和維修設施會畫。

## 未完成

- **範圍測試物件**（`parcel_drop_range_test.con.lua`）
  - 帶一個只有單一月台的車站，放置時可以畫出收件範圍。
  - 月台車道設成可連接，也接不上街道中段。現在改成不連接，並關掉所有裝卸，讓它對路線沒有用處。
  - 待確認：裝卸全關後範圍圈是否仍會顯示、路線工具是否仍列出這個站。確認後再併入正式投遞箱。
- **跨城包裹分揀中心**：維修設施外觀的版本已在遊戲中確認可以運作（2026-10-24）。換成倉庫外觀、加上工人與視窗卡片後還沒測試，待確認：
  - 倉庫模型、地面、圍籬是否完整，庫存模型是否隨庫存顯示貨物。
  - 四張卡片是否都正常顯示。
  - 進口產出的包裹是否可能被路由到其他城鎮的出口分揀中心。
- **效能優化（已退回）**：2026-10-27 試過一輪效能優化（除錯開關與 `deploy.ps1 -Release`、建造事件觸發的投遞處掃描、城鎮建築網格查找與 30 秒間隔、新投遞箱初始最低效率、除錯版計時 log）。使用者覺得 FPS 反而變低，原因沒確認，整批退回優化前的程式。優化版完整保存在 git 分支 `performance-optimization`（`git diff main performance-optimization` 可看全部差異），要再優化時先從那裡挑單項、逐項測 FPS。2026-10-27 起在 main 逐項加回，每一項一個 commit，量測結果存在 `perf\`。
- **城市包裹需求係數**：改成 2 之後的實際效果還沒驗證。
