

# 02\_dnsrecord\_flow — DNSRecord 物件流與封包結構

目標：看懂 **DNS 封包** 的基本結構，理解 `dnslib.DNSRecord` 的 parse → reply → pack 流程，能正確讀出問題、組出答案、設定旗標與狀態碼，最後回給客戶端。
資料流仍固定：`bytes → parse → policy → DSA(core) → policy → encode → bytes`。

---

## 1) DNS 訊息結構（速覽）

DNS 封包由 **Header（12 bytes）** + 四個區段組成：

```
+------------------+
| Header (ID, flags, counts)
+------------------+
| Question         |  一般只有 1 筆：QNAME, QTYPE, QCLASS
+------------------+
| Answer           |  0..N 筆 RR
+------------------+
| Authority        |  0..N 筆 RR（授權/委派）
+------------------+
| Additional       |  0..N 筆 RR（附加資訊／glue）
+------------------+
```

常見旗標 / 欄位（挑重點）：

* `ID`：請求/回應對齊的識別碼（16 位元）。
* `QR`：0=Query，1=Response。
* `AA`：Authoritative Answer（本伺服器對該名稱具權威）。
* `RD/RA`：Recursion Desired / Available（要求/提供遞迴）。
* `RCODE`：回應碼（0=NOERROR, 3=NXDOMAIN, 2=SERVFAIL…）。

**練習題**

* 寫出 `QR`、`AA`、`RCODE` 的中文一句話定義與典型用法。

---

## 2) dnslib 類別對應（怎麼把 bytes 變成物件）

`dnslib` 把 DNS 封包映射成幾個核心物件：

| 概念     | 類別/欄位（dnslib）                    | 備註                                |
| ------ | -------------------------------- | --------------------------------- |
| 整體封包   | `DNSRecord`                      | 最高層容器                             |
| 表頭     | `DNSRecord.header` (`DNSHeader`) | `id`,`qr`,`aa`,`rd`,`ra`,`rcode`… |
| 問題     | `DNSRecord.q` (`DNSQuestion`)    | `qname`,`qtype`,`qclass`          |
| 記錄（RR） | `RR` + rdata（`A`,`AAAA`,`MX`…）   | 用 `add_answer/add_auth/add_ar` 加  |

**練習題**

* 寫出 `DNSQuestion` 裡三個欄位分別代表什麼。

---

## 3) parse：bytes → `DNSRecord`

最小讀法（在 handler 內部）：

```python
request = DNSRecord.parse(data)  # data 來自 UDP
qname = str(request.q.qname)     # 例如 "example.lab."
qtype = QTYPE[request.q.qtype]   # 例如 "A"
```

可觀察 header 與區段：

```python
req_id   = request.header.id
is_query = (request.header.qr == 0)
# print(request)  # 也能快速 dump 結構
```

**練習題**

* 寫一行把 `qname` 轉小寫並確保帶尾點（FQDN）以便比對。

---

## 4) reply：基於請求建立回應骨架

`request.reply()` 會複製必要 header（含 `id`）、設定 `QR=1`，其他旗標你可自行調整：

```python
reply = request.reply()
reply.header.aa = 1   # 我方是權威來源（對 zone 內名稱）
reply.header.ra = 0   # 本例不提供遞迴
reply.header.rcode = 0  # 預設 NOERROR
```

**練習題**

* 什麼情況應把 `aa` 設為 1？什麼情況設為 0？

---

## 5) 組 Answer / Authority / Additional

加入一筆 Answer（A 記錄）：

```python
reply.add_answer(RR(qname, QTYPE.A, rdata=A("127.0.0.1"), ttl=60))
```

加入 Authority（例：NS）與 Additional（例：對應 A 的 glue）：

```python
reply.add_auth(RR("lab.", QTYPE.NS, rdata=NS("ns1.lab."), ttl=600))
reply.add_ar(RR("ns1.lab.", QTYPE.A, rdata=A("192.0.2.53"), ttl=600))
```

> 你也可以加 `AAAA/TXT/MX/...`，rdata 換成對應類別即可（`AAAA("::1")`, `TXT("hello")`, `MX(10,"mail.lab.")`）。

**練習題**

* 為 `foo.lab.` 同時回 `A` 與 `AAAA`，TTL 各自不同；再加一筆 Authority 的 `NS foo.lab. → ns.foo.lab.` 與 Additional 的 `A ns.foo.lab. → 192.0.2.99`。

---

## 6) pack：`DNSRecord` → bytes

把 `reply` 打包並送回：

```python
out = reply.pack()             # bytes
sock.sendto(out, self.client_address)
```

檢查封包大小（避免超出 UDP 常見安全上限 512 bytes；EDNS 另議）：

```python
if len(out) > 512:
    # 考慮截斷 TC 或改用 TCP；教學階段可先不用
    pass
```

**練習題**

* 寫一行檢查 `len(out)` 並在超過 512 時在註解裡說出兩種處理策略。

---

## 7) RCODE：回應碼（錯誤/狀態）

常見值：

* `0` NOERROR：有/無答案都可能是 NOERROR（例如存在但 `NODATA`）。
* `3` NXDOMAIN：名稱不存在（權威應同時回 SOA 於 Authority；教學期可略）。
* `2` SERVFAIL：伺服器內部錯誤或上游失敗。

設定方式：

```python
reply.header.rcode = 3  # NXDOMAIN
```

**練習題**

* 何時使用 NXDOMAIN、何時使用 NOERROR+空答案？各舉一例。

---

## 8) RD/RA：遞迴旗標

* `RD`（client 設）：「我想要遞迴」。
* `RA`（server 設）：「我提供遞迴」。
* 本教學的「權威最小伺服器」：通常 `RA=0`；將來做迭代解析器時才考慮遞迴行為。

**練習題**

* 若你的伺服器僅權威不遞迴，`RD` 和 `RA` 應該呈現什麼組合？

---

## 9) ANY 查詢（`QTYPE=ANY`）的教學策略

* 教學版可「把該名稱下有的型別都回」。
* 實務上為避免濫用或放大攻擊，常限制或拒絕 ANY。

**練習題**

* 寫出你在教學版 `server.py` 中處理 ANY 的簡單邏輯（幾句 pseudo-code 即可）。

---

## 10) 在 `handle()` 裡的最小骨架（對照 01 篇）

```python
def handle(self):
    data, sock = self.request

    # parse
    request = DNSRecord.parse(data)
    qname = str(request.q.qname).lower()
    qtype = QTYPE[request.q.qtype]

    # reply skeleton
    reply = request.reply()
    reply.header.aa = 1
    reply.header.ra = 0
    reply.header.rcode = 0  # 先假設 NOERROR

    # policy + DSA(core)
    if qtype in ("A", "ANY") and qname in ZONE:
        reply.add_answer(RR(qname, QTYPE.A, rdata=A(ZONE[qname]), ttl=60))
    else:
        # 視情況：空答案或 NXDOMAIN
        # reply.header.rcode = 3  # 若名稱不存在可考慮 NXDOMAIN
        pass

    # encode
    sock.sendto(reply.pack(), self.client_address)
```

**練習題**

* 將上面「空答案」改為「NXDOMAIN」的判定規則，補足你心目中的最小正確性。

---

## 11) 調試口訣（小雷與對策）

* **NOERROR 但沒 ANSWER**：可能是 `qtype` 不合或 `ZONE` 中無該型別；也可能 `qname` 大小寫/尾點未標準化。
* **AA 沒設**：你是權威就設 `aa=1`，否則部分工具輸出會讓人困惑。
* **ID 不對**：不要自己新建 `DNSRecord()`，用 `request.reply()` 保證 ID 與 header 對齊。
* **太大**：`len(out) > 512`，考慮截斷或 TCP。
* **TTL 誤會**：TTL 只是宣告值，真正倒數在 client/遞迴層。

**練習題**

* 寫出你自己的「三條排錯優先序」。

---

## 12) 測試清單（最小 pytest 想法）

* **典型**：`A` 查詢 → 一筆 Answer，`RCODE=0`，`AA=1`。
* **ANY**：同名稱下多型別 → Answer 至少含兩型別。
* **名稱不存在**：`RCODE=3`（若你選擇如此）、Answer 為空。
* **旗標**：請求 `RD=1`，回應仍 `RA=0`（教學權威伺服器）。

**練習題**

* 寫一個你會加的「最小端到端」測試名稱與預期斷言（assert 清單）。

---

## 13) 小結

`DNSRecord` 流程只有三步：**parse → reply → pack**。
你在中間加上 **policy/DSA** 就能得到一個可維護、可測的最小 DNS 伺服器；之後把 dict 換成七個 DSA（Hit/TTL/LRU/Timer/Inflight/NS/Visited），外層流程完全不需要改。

---

## 收尾 Commit

```bash
git add docs/tutorials/02_dnsrecord_flow.md
git commit -m "docs: add 02_dnsrecord_flow (DNSRecord parse/reply/pack; flags; RCODE; exercises)"
```

完成這篇後，你已懂得用 `DNSRecord` 驗收與組包；接下來的每個功能，只是在 **parse↔pack** 之間插入更聰明的「決策與資料結構」。
