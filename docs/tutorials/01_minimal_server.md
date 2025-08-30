

# 00\_env\_setup — 本地環境與最小驗證

目標：在 macOS 上建立**隔離的 Python 環境**，安裝必要套件，啟動最小 DNS 伺服器，並用 `dig` 做端到端驗證與留存證據（log、輸出檔）。
本專案的資料流固定為：`bytes → parse → policy → DSA(core) → policy → encode → bytes`。

---

## 0) 先釐清：虛擬環境 v.s. 虛擬機

**是什麼**

* **虛擬環境（venv）**：專案內私有的 Python 與套件夾，避免與系統或其他專案衝突。
* **虛擬機（VM）**：像一台獨立電腦。本文使用 venv，不是 VM。

**為什麼**

* 可重現、可控，升級或回退套件不會污染整機。

**怎麼做**

* 啟動 venv 後 shell 會出現 `(.venv)` 前綴，所有 `python`、`pip`、工具指令都會走 `.venv/bin`。

**練習題**

* 一句話各自定義 venv 與 VM。舉一個你會選 VM 而非 venv 的情境。

---

## 1) 建立與啟動 venv

**怎麼做**

```bash
python3 -m venv .venv
source .venv/bin/activate
python -V
```

**你應該看見**

* 終端提示出現 `(.venv)`。`python -V` 顯示版本（建議 3.11 或 3.12）。

**練習題**

* 專案 A、B 需要不同版本的 `dnslib`，如何用 venv 避免互相干擾？

### 1.5) venv 概念圖（速記版）

```
[macOS / Shell]
      |
      |  PATH → .venv/bin 優先
      v
 .venv/bin/python  ── 執行你的程式與工具（pytest 等）
        |
        v
 .venv/lib/.../site-packages   ← 依賴只安裝在這裡
        |
        v
   檔案 / 網路 / OS API  ← 對外互動照常，不受 venv 限制
```

---

## 2) 安裝必要套件：`dnslib` 與 `pytest`

**是什麼**

* `dnslib`：DNS 封包解析與組包。
* `pytest`：測試框架。

**怎麼做**

```bash
pip install --upgrade pip
pip install dnslib pytest
```

**練習題**

* 為何只靠 `dnslib` 與 `pytest` 就能起跑？各自扮演什麼角色？

---

## 3) 健康檢查：測試能不能跑

**怎麼做**

```bash
pytest -q | tee shell.log
```

**你應該看見**

* 測試摘要與結果，同步存成 `shell.log`，方便回溯。

**練習題**

* 寫出「一邊看輸出、一邊存檔」的兩種做法。

---

## 4) 啟動最小 DNS 伺服器（權威、回應 example.lab）

**是什麼**

* 最小 UDP 伺服器，綁定 `127.0.0.1:8053`，固定回 `example.lab.` 的 A 記錄為 `127.0.0.1`。
* 你可以直接用專案根的 `server.py`。

**怎麼做（視窗一，保持開著）**

```bash
python server.py
# 預期輸出：DNS server running at 127.0.0.1:8053 ...
```

**練習題**

* 為何建議用 8053 而不是 53？說出兩個理由（權限與安全性）。

---

## 5) 用 `dig` 做端到端驗證並留證據

**怎麼做（視窗二）**

```bash
dig @127.0.0.1 -p 8053 example.lab A | tee dig_output.txt
```

**你應該看見**

* `status: NOERROR`
* `ANSWER SECTION: example.lab.  60  IN  A  127.0.0.1`
* 同時存成 `dig_output.txt` 以便提交與回放。

**練習題**

* 若 `NOERROR` 但沒有 `ANSWER SECTION`，列出三個排查點。

---

## 6) 最小 Commit：把證據鎖進歷史

**怎麼做**

```bash
git add shell.log dig_output.txt
git commit -m "env+obs: venv healthy; captured dig ANSWER for example.lab"
```

**為什麼**

* 建立**可見回饋**與**可回溯歷程**，維持節奏。

**練習題**

* 一句話寫出「小圈工作律」並說明對動力的實際好處。

---

## 7) 常見錯誤與快修

**症狀與修法**

* `ModuleNotFoundError: dnslib` → 還沒在 venv 裝：`pip install dnslib`。
* `Address already in use` → 埠被佔用：`lsof -i UDP:8053` 找 PID，`kill <PID>`。
* `command not found: dig_output.txt` → 你把檔名接在 `|` 後面；改用 `> dig_output.txt` 或 `| tee dig_output.txt`。
* `NOERROR` 但沒 answers → 檢查 `ZONE` 是否 `"example.lab."`（含尾點），以及查詢 `qtype` 是否 `A` 或 `ANY`。

**練習題**

* 解釋為何 `| dig_output.txt` 會出錯，並寫出三種正確存檔方式（覆寫、追加、鏡射）。

---

## 8) 設計護欄：固定資料路徑與分層

**規則**

* 單一時間來源、I/O 與核心分離、固定資料路徑：
  `bytes → parse → policy → DSA(core) → policy → encode → bytes`。
* 先確立不變量與終止性，再擴充功能與優化。

**練習題**

* 為何先固定資料路徑，再逐步擴充 DSA 模組，能讓系統更好測試與維護？

---

## 9) 到此為止你應該擁有的檔案

* `.venv/`（虛擬環境）
* `shell.log`（健康檢查輸出）
* `dig_output.txt`（端到端驗證輸出）

**練習題**

* 明天換一台電腦，如何利用這三樣東西迅速重建並驗證今天的結果？

---

## 10) 下一步建議

* 在 `dns_core/ds/` 為七個資料結構補上「最小 API + 一句不變量」的檔頭 docstring，並新增基本測試。
* 在 `docs/tutorials/01_minimal_server.md` 繼續說明 `DNSRecord.parse → reply → pack` 的物件流與 `RR/A/QTYPE` 的角色。

**練習題**

* 寫出 `cache_tbl` 模組你想公開的三個最小方法與一句不變量。為什麼需要這三個？

---

# 附錄 A：Python venv 概念圖（完整版）

## A.1 大局：誰跟誰連在一起

```
[macOS / Shell]
      |
      |  (PATH 被改：.venv/bin 放最前面)
      v
 .venv/bin/python ───────────────┐
        |                        |
        |  執行你的程式          |  console scripts（pip 安裝）
        v                        v
   [your code]             .venv/bin/<tool>
        |                        |
        |  import                |  也會 import
        v                        v
 .venv/lib/pythonX.Y/site-packages  （依賴專用倉庫）
        |
        |  只跟檔案/網路/OS 互動（正常系統呼叫）
        v
  [檔案系統 / 網路 / OS API]
```

**要點**

* 啟動 venv 後，PATH 讓 `.venv/bin` 優先，`python/pip/pytest` 都走這套。
* 套件安裝到 `.venv/lib/.../site-packages`，不碰全域。
* 對外互動照常；隔離的只有 Python 執行環境與依賴。

## A.2 啟動與停用：PATH 如何被切換

```
source .venv/bin/activate
        │
        ├─ 設定 VIRTUAL_ENV=.venv
        └─ 修改 PATH=".venv/bin:原 PATH"

deactivate
        └─ 還原 PATH 與提示字首
```

**檢查口令**

```
which python
python -c "import sys; print(sys.prefix)"
python -m site
```

## A.3 匯入路徑與封裝位置

```
啟動順序（簡化）：
  1) 啟動 .venv/bin/python
  2) 讀 .venv/pyvenv.cfg（定位 base）
  3) 設定 sys.prefix = .venv
  4) 建立 sys.path：
     - 當前目錄（你的 repo）
     - .venv/lib/pythonX.Y/site-packages
```

## A.4 pip 的寫入與工具腳本

```
python -m pip install <pkg>
         │
         ├─ → .venv/lib/pythonX.Y/site-packages/<pkg>/
         └─ → .venv/bin/<pkg-命令>（console script）
```

## A.5 與外界的邊界（記住這張）

```
[全域 Python / 全域 site-packages]   ← 預設不使用
                 ▲
                 │（邊界：PATH 與 sys.path 被 venv 接管）
                 │
      .venv  ←——─┘
       │
       ├─ 決定「解譯器」與「依賴」來源
       └─ 不限制 I/O：檔案、網路、OS 一切照常
```

## A.6 60 秒自我測驗

1. 啟動 venv 後，`which python` 會指到哪裡
2. `pip install dnslib` 會安裝到哪個路徑
3. 為何 `dig` 等系統工具不受 venv 影響
4. 若 `pytest` 找不到，先檢查什麼（提示：PATH 與 `python -m pip`）

---

完成後建議直接 commit：

```bash
git add docs/tutorials/00_env_setup.md
git commit -m "docs: add 00_env_setup with venv concept diagrams and exercises"
```
