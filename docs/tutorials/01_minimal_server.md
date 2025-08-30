太好了～我把「手寫筆記的精華」（精確用語、四層剝洋蔥、外部/內部骨幹＋極簡線圖）整合進你的原始文件，保持最小示例不變，只加上更精準的資料流與可選重構段落。

---

# 01\_minimal\_server — 最小 DNS 權威伺服器

目標：用最少的程式碼把「本機 UDP:8053 → 回答 `example.lab` 的 A 記錄」跑起來，並看懂每一行在幹嘛。
**資料流固定（精確版）**：`UDP payload → parse(DNSRecord) → policy → DSA(core) → encode(bytes) → sendto`

---

## 1) 我們要做什麼（一句話）

在你的電腦上開一個 UDP 伺服器聽 8053 埠，任何人來問 `example.lab` 的 A 記錄，就回 `127.0.0.1`，TTL=60。

**練習題**

* 用自己的話重述上面那句話，不超過 15 個字。

---

## 2) 檔案與工具

* **`server.py`**：最小伺服器入口。
* **`dnslib`**：parse/encode DNS 封包。
* **標準庫 `socketserver`**：UDP 伺服器框架。
* **`dig`**：驗證工具。

**練習題**

* 說出 `dnslib` 和 `socketserver` 在本專案各扮演什麼角色。

---

## 3) 先看整體流向（ASCII 圖）

```
[dig 客戶端]
   |
   v  UDP 127.0.0.1:8053
[socketserver.UDPServer]
   |
   v  呼叫
[DNSHandler.handle()]
   |
   v  reply.pack() → bytes
[UDP 回傳給 dig]
```

旁邊掛著最小資料庫（HashMap）：

```
[ZONE dict: {"example.lab.": "127.0.0.1"}]
     ^                             |
     |———(查表 O(1))———————|
```

**練習題**

* 上圖中，哪一格是「核心行為」會成長的地方？為什麼？

### 3.1 四層剝洋蔥（極簡速寫圖｜背口訣用）

```
Client → recvfrom → handle(parse→policy→DSA→encode) → sendto → Kernel/NIC → Client
          L2               L1                               L2               L3/L4
```

> 口訣：**L1 做語意；跨界只經 L2；搬比特交給 L3/L4。**
> `recvfrom` 是耳朵（框架代呼，拿 UDP payload），`sendto` 是嘴巴（我們呼，把回應 bytes 交 kernel）。

---

## 4) 程式碼（逐段解剖）

```python
from dnslib import DNSRecord, RR, A, QTYPE
import socketserver

# 4.1 迷你資料庫：FQDN → IPv4
ZONE = {
    "example.lab.": "127.0.0.1",
}

# 4.2 每包 UDP 資料都會交給這個 handler
class DNSHandler(socketserver.BaseRequestHandler):
    def handle(self):
        data, sock = self.request

        # parse：bytes → DNSRecord
        request = DNSRecord.parse(data)

        # policy：抽出「問誰」「問哪種記錄」
        qname = str(request.q.qname)
        qtype = QTYPE[request.q.qtype]

        # 建回應骨架（沿用 request 的 header/ID）
        reply = request.reply()

        # DSA(core)：目前用 ZONE (dict) 查表；只回 A/ANY
        if qname in ZONE and qtype in ("A", "ANY"):
            # encode：組 Answer（A 記錄、TTL=60）
            reply.add_answer(RR(qname, QTYPE.A, rdata=A(ZONE[qname]), ttl=60))

        # encode：物件 → bytes，送回給 client
        sock.sendto(reply.pack(), self.client_address)

# 4.3 啟動 UDP 伺服器：本機 127.0.0.1:8053
if __name__ == "__main__":
    server = socketserver.UDPServer(("127.0.0.1", 8053), DNSHandler)
    print("DNS server running at 127.0.0.1:8053 ...")
    server.serve_forever()
```

對應資料流（精確化）：

* **parse**：`DNSRecord.parse(data)`（`data` 是 **UDP payload**）
* **policy**：檢查 `qname` / `qtype`
* **DSA(core)**：用 `ZONE` 這個 dict 查表（之後換成七個 DSA 模組）
* **encode**：`reply.add_answer(...)` → `reply.pack()` → `sock.sendto(...)`

**練習題**

* 把上面四個步驟各用 1 行註解寫回你的 `server.py`。

### 4.4（可選）外部/內部分層骨幹（保留原功能，利於擴充/測試）

> **目的**：`handle()` 只搬 bytes；核心邏輯收 bytes 回 bytes，方便測試與未來熱插拔七件套。

```python
def core_dns(bytes_in: bytes) -> bytes:
    request = DNSRecord.parse(bytes_in)
    qname   = str(request.q.qname)
    qtype   = QTYPE[request.q.qtype]
    reply   = request.reply()
    if qname in ZONE and qtype in ("A","ANY"):
        reply.add_answer(RR(qname, QTYPE.A, rdata=A(ZONE[qname]), ttl=60))
    return reply.pack()

class DNSHandler(socketserver.BaseRequestHandler):
    def handle(self):
        data, sock = self.request
        sock.sendto(core_dns(data), self.client_address)
```

> **邊界守則**：I/O 不做決策；核心不碰 socket/時鐘。

---

## 5) 跑起來與驗證

視窗一（保持開著）：

```bash
python server.py
# 預期：DNS server running at 127.0.0.1:8053 ...
```

視窗二（敲它，並留存證據）：

```bash
dig @127.0.0.1 -p 8053 example.lab A | tee dig_output.txt
# 預期：ANSWER SECTION 裡有 127.0.0.1
```

**練習題**

* 解釋為何要兩個視窗。只有一個視窗會遇到什麼麻煩？

---

## 6) 物件與函式：最小集合

* `DNSRecord.parse(bytes)`：bytes → DNS 封包物件。
* `request.q.qname`、`request.q.qtype`、`QTYPE[...]`：抽出查詢名字與型別字串。
* `request.reply()`：產生回應骨架（沿用 ID）。
* `RR(...)`、`A(...)`：組 A 記錄的答案。
* `reply.pack()`：封包物件 → bytes。
* `socketserver.UDPServer`、`BaseRequestHandler.handle()`：I/O 邊界。
* **`recvfrom`/`sendto`（觀念）**：耳朵/嘴巴；經由 kernel 取回/交付 UDP payload。

**練習題**

* 寫出上述任意 3 個項目的「一句話中文定義」。

---

## 7) ZONE 就是 HashMap（為何用 dict？）

* `ZONE` 是 Python `dict`（HashMap）。Key=FQDN（`"example.lab."`），Value=IPv4 字串。
* 平均查詢 O(1)，非常適合最小示範。
* 之後會替換為「快取三件套 + timer + inflight + ns\_ring + visited」。

**練習題**

* 在 `ZONE` 中再加 `foo.lab.` → `127.0.0.2`，用 `dig` 驗證。

---

## 8) 常見錯誤與快速排查

* `ModuleNotFoundError: dnslib` → 沒在 venv 裝：`pip install dnslib`。
* `Address already in use` → 8053 被占用：

  ```bash
  lsof -i UDP:8053   # 找 PID
  kill <PID>
  ```
* `NOERROR 但沒 ANSWER` → 檢查三件事：

  1. `ZONE` key 是否 `"example.lab."`（尾點必須有）；
  2. 查的是 `A` 或 `ANY`；
  3. 伺服器視窗是否在跑。
* `command not found: dig_output.txt` → 你把檔名接在 `|` 後面；改用 `> dig_output.txt` 或 `| tee dig_output.txt`。

**練習題**

* 寫出你的「三步排錯口訣」。

---

## 9) 兩個微調練習（加肌肉記憶）

**練習 A：改 TTL**

* 把 `ttl=60` 改為 `ttl=10`，`dig` 兩次間隔 11 秒，觀察 TTL 是否重置。

**練習 B：支援 AAAA**

* 讓 `ZONE` 同時能回 `AAAA`（IPv6，如 `::1`）。
* 判斷 `qtype == "AAAA"`，用 `dnslib` 的 `AAAA()` rdata 組記錄。

---

## 10) 為何要先把這個跑起來

* 這不到 50 行的程式碼，完整呈現固定資料流與 I/O 邊界。
* 明天把「DSA(core) 那一格」換成 `cache_tbl`、`ttl_heap` 等模組，外圍流程不變。
* 好處：可測、可擴充、可回放；新功能只往核心加，不動邊界。

**練習題**

* 用 1–2 句話，描述「固定資料流」對寫測試的具體好處。

---

## 11) 收尾：把證據鎖進歷史

```bash
git add dig_output.txt
git commit -m "run: minimal authoritative server (server.py); capture dig output"
```

**練習題**

* 把今天學到的 3 個關鍵詞寫進 commit message（不超過 72 字元）。

---

## 12) dnslib × socketserver 互動圖（線段版）

### 12.0 極簡線段（放大一次即可背）

```
Client → recvfrom → handle(parse→policy→DSA→encode) → sendto → Kernel/NIC → Client
```

### 12.1 整體時序（Sequence）

```
[dig 客戶端]
      |
      |  UDP 封包 (DNS Query)
      v
[socketserver.UDPServer @ 127.0.0.1:8053]
      |
      |  呼叫
      v
[DNSHandler.handle(self)]
      |
      | 1) bytes -> 解析
      |    request = dnslib.DNSRecord.parse(data)
      |
      | 2) 取問題
      |    qname = str(request.q.qname)
      |    qtype = dnslib.QTYPE[request.q.qtype]   # "A"/"AAAA"/...
      |
      | 3) 建回應骨架
      |    reply = request.reply()
      |
      | 4) 組 Answer（僅示範 A）
      |    rr = dnslib.RR(qname, dnslib.QTYPE.A,
      |                   rdata=dnslib.A("127.0.0.1"), ttl=60)
      |    reply.add_answer(rr)
      |
      | 5) 封包 -> bytes
      |    out = reply.pack()
      |
      | 6) 回傳
      v
sock.sendto(out, client_address)
      |
      v
[dig 收到 UDP 回應 (DNS Answer)]
```

重點對位：

* **socketserver** 管 **收/送與 handler 回呼**。
* **dnslib** 管 **DNS 封包物件化（parse/reply/pack）與 RR 組裝**。
* 你的 **核心行為（policy/DSA）** 就夾在兩者之間（查表/快取/逾時/輪替…）。

### 12.2 物件／函式接點（誰呼叫誰）

```
socketserver.UDPServer
  └─> DNSHandler.handle(self)
        ├─ data, sock = self.request
        ├─ request = dnslib.DNSRecord.parse(data)      # bytes -> DNSRecord
        ├─ qname  = str(request.q.qname)               # 問題名稱
        ├─ qtype  = dnslib.QTYPE[request.q.qtype]      # 問題型別字串
        ├─ reply  = request.reply()                    # 回應骨架 (複 header/ID)
        ├─ rr     = dnslib.RR(qname, dnslib.QTYPE.A,
        │                     rdata=dnslib.A("127.0.0.1"), ttl=60)
        ├─ reply.add_answer(rr)                        # 加一筆 Answer
        ├─ out    = reply.pack()                       # DNSRecord -> bytes
        └─ sock.sendto(out, self.client_address)       # 發回 UDP
```

### 12.3 與固定資料路徑對齊

```
UDP payload ──parse──> request(DNSRecord)
           policy    : 檢查 qname/qtype
           DSA(core) : 目前用 dict 查表；將來改快取/TTL/Timer/NS 等
request.reply()      : 組 RR / add_answer(...)
encode ──pack──> bytes ──sendto──> 客戶端
```

**練習題**

1. 在上圖標出你未來要插入的 3 個 DSA 模組位置（例如 Hit/TTL/LRU）。
2. 將「支援 AAAA」加入時序：哪幾步需要改動，哪幾步不動？
3. 若要改成非同步（`asyncio`），哪一側影響最大（socketserver 還是 dnslib）？為什麼？

---

## 13) 附錄：`handle()` 內部的關係圖（細流）

```
(data bytes, sock) = self.request
          |
          v
  DNSRecord.parse(data)  →  request
          |                        |
          |                        v
          |                   request.q.qname → qname
          |                   request.q.qtype → QTYPE[...] → qtype
          |
          v
     reply = request.reply()
          |
          |  if (qname ∈ ZONE and qtype ∈ {"A","ANY"})
          |        |
          |        v
          |   RR(qname, QTYPE.A, rdata=A(ZONE[qname]), ttl=60)
          |        |
          |        v
          |   reply.add_answer(...)
          |
          v
     bytes_out = reply.pack()
          |
          v
  sock.sendto(bytes_out, client_address)
```

---

**收尾建議**

```bash
git add docs/tutorials/01_minimal_server.md
git commit -m "docs: refine dataflow (UDP payload→parse→policy→DSA→encode→sendto) and add minimal onion/IO-core split diagrams"
```

完成 ✅ 這版把**手寫筆記的精華**全收進來了，但保持 01 的「最小可跑」不變；後續要升級 02/03 只動核心，不動外框。
