# dns-dsa-lab

以 **Python（macOS）** 實作的 **DNS × 資料結構與演算法（DSA）** 教學與實驗專案。

* 目前可用：最小「權威」DNS 伺服器（回應 `example.lab`）
* 核心目標：以「七個資料結構」為骨架，建出可自行往上查詢的**迭代式解析器**，強調可讀、可測、可重用

---

## 目錄

* [專案目的](#專案目的)
* [你能獲得什麼](#你能獲得什麼)
* [功能總覽](#功能總覽)
* [架構概覽](#架構概覽)
* [七個資料結構（核心）](#七個資料結構核心)
* [資料夾結構](#資料夾結構)
* [環境需求](#環境需求)
* [快速開始](#快速開始)
* [使用方式](#使用方式)
* [開發與測試](#開發與測試)
* [設計原則](#設計原則)
* [Roadmap](#roadmap)
* [非目標](#非目標)
* [貢獻指南](#貢獻指南)
* [授權與安全](#授權與安全)

---

## 專案目的

將 **DNS 行為**壓縮到**七個資料結構**的最小骨架中，建立一個清楚、可測試、可重用的實作模板，讓協議行為與資料結構的不變量可以一一對齊。

基本工程規範：

* 時間由外部注入，核心不直接讀系統時鐘
* I/O 與核心行為分離，封包解析與編碼在邊緣層
* 固定資料路徑：`bytes → parse → policy → DSA(core) → policy → encode → bytes`

透過本專案，你可以觀察並驗證逾時、重試、CNAME 鏈、防循環、NS 輪替等行為如何落在 Map、Heap、DList、Ring、Set 的結構保證上。

---

## 你能獲得什麼

**學習與參考**

* 一條從最小權威伺服器到迭代式解析器的分階段實作路線，附自動化測試
* 乾淨的工程骨架：`server_api.py` 為門面，`dns_core/` 為核心邏輯，`net_io/` 為 I/O

**可重用元件**

* 七個資料結構的獨立模組與單元測試，責任清晰
* 端到端測試樣式，可作為課程、面試或原型開發的範本

**即刻可用**

* 本機可跑的最小權威 DNS 伺服器，適合觀察 DNS 封包與 TTL、LRU 行為

  * 檔案：`examples/server_authoritative_min.py`

---

## 功能總覽

**已具備**

* 在本機 `127.0.0.1:8053` 監聽 UDP
* 回應 `example.lab` 的 `A` 記錄
* 簡潔可讀的最小伺服器，適合教學與練習

**規劃中（迭代式解析器）**

* 逐層查詢 root、TLD、權威伺服器
* 快取三件套：Hit、TTL、LRU，含負快取（NXDOMAIN、NODATA）
* 中央化逾時與重試，公平 NS 輪替與退避策略
* CNAME 走訪與循環防護
* 可觀測性指標：hit 或 miss、重試次數、逾時數、淘汰數，並提供端到端測試

---

## 架構概覽

對外由 `server_api.py` 提供單一 API。核心解析器 `dns_core/resolver.py` 串接七個資料結構模組。封包解析與編碼在 `net_io/`，設定在 `config/`，共用工具如時間、日誌在 `util/`，測試在 `tests/`。

固定資料路徑：

```
bytes → parse → policy → DSA(core) → policy → encode → bytes
```

單一時間來源：核心透過注入的 `now` 參數取得時間（見 `util/clock.py`），利於測試與重現。

---

## 七個資料結構（核心）

| 名稱與模組                 | 結構          | 角色            | 關鍵不變量                 |
| --------------------- | ----------- | ------------- | --------------------- |
| Hit（`cache_tbl.py`）   | Map         | 以前是否回答過此問題    | 同一鍵最多一筆有效答，過期即 miss   |
| TTL（`ttl_heap.py`）    | Min-Heap    | 誰先過期先處理       | 堆頂是最早 deadline，彈出次序單調 |
| LRU（`lru_dlist.py`）   | DList       | 最久沒被用者先丟      | 命中移到表頭，淘汰從表尾          |
| 合併（`inflight_map.py`） | Map         | 同題只派一人外送      | 同鍵僅一個外送任務存活           |
| 期限（`timer_heap.py`）   | Min-Heap    | 哪個逾時先觸發       | 事件依 deadline 非遞減順序觸發  |
| 候選（`ns_ring.py`）      | Ring 或 List | 公平輪替詢問 NS 並退避 | 指針輪替，失敗提高懲罰或退避        |
| 依存（`visited_set.py`）  | Set         | CNAME 鏈防循環    | 單鏈不重複，深度上限預設 16       |

---

## 資料夾結構

```
dns-dsa-lab/
├─ README.md
├─ pyproject.toml                  # 或 requirements.txt
├─ run_server.py                   # 迭代式解析器入口（啟用後改跑此檔）
├─ server_api.py                   # 對外門面：resolve()、metrics() 等
├─ config/
│  ├─ bootstrap_ns.json            # 初始 root、TLD 名單
│  └─ settings.py                  # 逾時、重試、資源上限等參數
├─ dns_core/
│  ├─ resolver.py                  # 串接七個資料結構的行為中樞
│  ├─ types.py                     # QueryKey、RRSet、Result 等共用型別
│  ├─ errors.py                    # 統一錯誤型別
│  └─ ds/                          # 七個資料結構的實作
│     ├─ cache_tbl.py              # Hit → Map
│     ├─ ttl_heap.py               # TTL → Min-Heap
│     ├─ lru_dlist.py              # LRU → DList
│     ├─ inflight_map.py           # 合併 → Map
│     ├─ timer_heap.py             # 期限 → Min-Heap
│     ├─ ns_ring.py                # 候選 → Ring 或 List
│     └─ visited_set.py            # 依存 → Set
├─ net_io/
│  ├─ udp_server.py                # UDP 收送
│  └─ codec/
│     ├─ parser.py                 # DNS 解析（可先用 dnslib，逐步替換）
│     └─ encoder.py                # DNS 組包
├─ util/
│  ├─ clock.py                     # 單一時間來源（可注入）
│  └─ logging_conf.py              # 日誌設定
├─ examples/
│  └─ server_authoritative_min.py  # 目前的最小權威伺服器
└─ tests/
   ├─ test_cache_tbl.py
   ├─ test_ttl_heap.py
   ├─ test_lru_dlist.py
   ├─ test_inflight_map.py
   ├─ test_timer_heap.py
   ├─ test_ns_ring.py
   ├─ test_visited_set.py
   └─ test_resolver_flow.py        # 端到端測試（含 CNAME 與轉介）
```

---

## 環境需求

* macOS 12 以上
* Python 3.10 以上，建議 3.11 或 3.12
* 套件與工具：`dnslib`、`pytest`。封包觀察可搭配 Wireshark 或 tcpdump

---

## 快速開始

### 最小權威伺服器（立即可跑）

```bash
python3 -m venv .venv
source .venv/bin/activate

pip install --upgrade pip
pip install dnslib pytest

python examples/server_authoritative_min.py
# 顯示：DNS server running at 127.0.0.1:8053 ...

dig @127.0.0.1 -p 8053 example.lab A
# 預期：
# ;; ANSWER SECTION:
# example.lab.  60  IN  A  127.0.0.1
```

### 迭代式解析器（啟用後）

```bash
python run_server.py
# 之後可查詢外部網域，伺服器將自行走 root、TLD、權威鏈
```

---

## 使用方式

* 本機實驗與教學：觀察查詢與回應的封包內容，練習 TTL 與 LRU 行為
* 專案樣板：在此骨架上擴充其他 DNS 行為，或將結構改裝到其他協議原型，仍保留以資料結構驅動核心行為的設計

---

## 開發與測試

**虛擬環境**

```bash
python3 -m venv .venv
source .venv/bin/activate
```

**安裝依賴**

```bash
pip install -r requirements.txt
# 或使用 pyproject.toml、uv、poetry 等管理方式
```

**執行測試**

```bash
pytest -q
```

**建議工具**

* 預設日誌層級為 INFO，除錯時可調為 DEBUG
* 建議設定 CI（例如 GitHub Actions）自動執行測試與型別檢查

---

## 設計原則

1. 單一時間來源：核心不直接讀系統時鐘，時間一律由外部注入
2. I/O 與核心分離：封包處理在 `net_io/`，核心僅負責行為與結構
3. 固定資料路徑：`bytes → parse → policy → DSA(core) → policy → encode → bytes`
4. 錯誤分層止血：語法錯誤止於解析層，資源與逾時止於計時層，門面層僅保證參數合法
5. 合併與逾時紀律：相同查詢必合併，所有逾時由 `timer_heap` 統一調度
6. 先保證再擴充：先確立不變量與終止性，再增加功能與優化

---

## Roadmap

* v0 完成：最小權威伺服器（`examples/server_authoritative_min.py`）
* v1：快取三件套（Hit、TTL、LRU）與單元測試
* v2：合併 Inflight 與逾時 Timer，加入重試策略
* v3：候選 NS 輪替與退避，依存集合防 CNAME 循環
* v4：整合解析器，支援一般 A 記錄解析與負快取（NXDOMAIN、NODATA）
* v5：觀測指標與完整端到端測試
* v6 可選：自研最小 codec、EDNS、TCP、指標介面

---

## 非目標

* 非完整生產級 DNS，不含 DNSSEC、DoT、DoH、AXFR 等
* 預設不使用 53 埠的 root 權限，採 8053 作為本機實驗埠
* 不做黑箱式實作，本專案偏向可讀、可測、可拆解的學習與工程骨架

---

## 貢獻指南

歡迎提出 Issue 與 Pull Request。請：

* 遵循現有目錄結構與命名慣例
* 為新模組與新行為補上對應的測試
* 在擴充前先寫清模組不變量與最小公開 API，避免耦合擴散

---

## 授權與安全

* 授權建議使用 MIT，並新增 `LICENSE` 檔案
* 53 埠需要高權限，建議於本機以 8053 埠進行實驗；若需對外使用 53，可在 macOS 以 `pf` 將 53 轉導至 8053 以避免提權
* 本專案用於教學與實驗，未針對公開網路服務進行完備加固，請審慎評估後再對外部署
