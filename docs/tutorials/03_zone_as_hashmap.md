

# 03\_zone\_as\_hashmap — 用 HashMap 表示 Zone

目標：把「DNS 區檔（zone）」壓成一個**可查表的 HashMap**（Python `dict`），先跑通最小行為，再逐步演化成可管理多筆記錄（RRSet）、多型別（A/AAAA/MX…）、TTL 的簡易資料模型。

---

## 1) 一句話總結

把 `FQDN → {type → [records]}` 存進一個 `dict`，查詢時看 `qname` 與 `qtype`，配對到就組 RR 回去。

**練習題**

* 用 10 個字內說出「為什麼用 HashMap 存 zone」。

---

## 2) Zone v.s. 我們的 `ZONE`（教學版）

* **真實世界的 Zone**：包含 SOA、NS、A/AAAA/MX/TXT…，有序列號、委派與授權邏輯。
* **我們的教學 `ZONE`**：就是一個 HashMap；先把「名稱對應記錄」函數化。
* **好處**：平均查詢 **O(1)**，易讀、易改、易長肌肉。

**練習題**

* 舉例：什麼是真實 zone 有而我們的 `ZONE` 沒有的資料或機制？

---

## 3) FQDN 尾點與大小寫標準化

* **尾點 `.`**：DNS 的正規名稱以 `.` 結尾（例如 `example.lab.`）。
* **大小寫**：DNS 名稱比對**不分大小寫**；建議把 `qname` 轉小寫後再查。
* **最小做法**：`qname = str(request.q.qname).lower()`；`ZONE` 的 key 也以小寫 FQDN 存。

**練習題**

* 若使用者問 `ExAmPlE.LaB A`，如何保證能命中 `ZONE` 的 `"example.lab."`？

---

## 4) 最小結構（v0）：單一類型的寫死回答

和 01 篇同款，只有 A 記錄，key → value 是一個 IP：

```python
ZONE = {
    "example.lab.": "127.0.0.1",
}
```

**限制**：不能同名放 AAAA、MX；TTL 也只能硬編在程式裡。

**練習題**

* 在 v0 結構下，如何讓 `foo.lab.` 也能回 `127.0.0.2`？

---

## 5) 進階結構（v1）：多型別 + 多筆記錄（RRSet）

把 value 升級成「型別 → 記錄列表」。每筆記錄可附帶 TTL：

```python
# FQDN 小寫、含尾點
ZONE = {
    "example.lab.": {
        "A":    [("127.0.0.1", 60), ("127.0.0.2", 60)],
        "AAAA": [("::1", 60)],
        # "MX":  [("10 mail.example.lab.", 300)],
        # "TXT": [("hello=world", 120)],
    },
    "foo.lab.": {
        "A":    [("192.0.2.10", 120)],
    },
}
```

查詢流程（概念）：

1. 取 `qname`、`qtype`
2. 命中 `ZONE[qname]`；
3. 若 `qtype` 存在，就把該型別的所有記錄逐一 `add_answer`；
4. 若 `qtype == "ANY"`，可回該名稱下所有型別（教學場景可行，實務上要謹慎）。

**練習題**

* 幫 `example.lab.` 加上 AAAA=`::1`，並用 `dig -t AAAA` 驗證。

---

## 6) 參考實作（取代 01 的 `ZONE` 與判斷段）

示範如何從 v1 結構組答案（片段，放進你的 `handle()` 內）：

```python
qname = str(request.q.qname).lower()
qtype = QTYPE[request.q.qtype]  # "A" / "AAAA" / "MX" / "ANY"...

reply = request.reply()

records = ZONE.get(qname)
if records:
    def add_rr(rr_type, rdata_str, ttl):
        if rr_type == "A":
            reply.add_answer(RR(qname, QTYPE.A, rdata=A(rdata_str), ttl=ttl))
        elif rr_type == "AAAA":
            reply.add_answer(RR(qname, QTYPE.AAAA, rdata=AAAA(rdata_str), ttl=ttl))
        elif rr_type == "MX":
            pref, host = rdata_str.split(" ", 1)
            reply.add_answer(RR(qname, QTYPE.MX, rdata=MX(int(pref), host), ttl=ttl))
        elif rr_type == "TXT":
            reply.add_answer(RR(qname, QTYPE.TXT, rdata=TXT(rdata_str), ttl=ttl))
        # 其他型別類推

    if qtype == "ANY":
        for rr_type, lst in records.items():
            for rdata_str, ttl in lst:
                add_rr(rr_type, rdata_str, ttl)
    else:
        lst = records.get(qtype)
        if lst:
            for rdata_str, ttl in lst:
                add_rr(qtype, rdata_str, ttl)
```

> 註：要 `from dnslib import DNSRecord, RR, A, AAAA, MX, TXT, QTYPE`。
> 記得 `MX` 的主機名也要用 FQDN（尾點）。

**練習題**

* 為 `foo.lab.` 加一筆 `MX`：優先序 10、主機 `mail.foo.lab.`；用 `dig -t MX foo.lab` 驗證。

---

## 7) TTL：只是「宣告值」，不是伺服器在倒數

* 伺服器只是把 TTL 寫入 RR；真正**倒數與快取**在**客戶端或遞迴解析器**。
* 教學版 `ZONE` 直接把 TTL 放在記錄旁即可；未來要「到期清掉」才需要把 TTL 交給 `ttl_heap` 等結構管理。

**練習題**

* 把 `example.lab.` 的 A 記錄 TTL 改成 10；兩次查詢相隔 11 秒，觀察 `dig` 顯示的 TTL 是否重置。

---

## 8) CNAME 的最小注意（先避坑）

* 標準要求：名稱若有 CNAME，**同名不可有其他型別**（DNSSEC 另計）。
* 教學最小策略：

  1. 若 `qtype=="CNAME"` 或該名稱有 `CNAME`，先回 CNAME；
  2. 你也可以順手把指向的 A/AAAA 放進**附加（Additional）**，但需要更完整的結構與語意。
* 初學階段：先**不要同名放 CNAME 與 A**，避免混淆。

**練習題**

* 為 `alias.lab.` 設 `CNAME` 指到 `example.lab.`；用 `dig -t CNAME alias.lab` 觀察行為。

---

## 9) ANY 查詢的策略（教學場景）

* `ANY` 不是「查全部網際網路」，只是「要這個名稱你有的所有型別」。
* 教學版可「把有的都回」；實務常因資安/效率限制而選擇性回應或拒絕。

**練習題**

* 對 `example.lab.` 下 `A` 與 `AAAA` 後，嘗試 `dig -t ANY example.lab`，觀察輸出。

---

## 10) 資料結構口訣與演化路線

* **v0**：`name → ip`（單型別，最小）
* **v1**：`name → {type → [(rdata, ttl), ...]}`（多型別、多筆）
* **v2**：把 `(rdata, ttl)` 的到期管理交給 **TTL → Min-Heap**（`ttl_heap`）
* **v3**：加入 **Hit → Map**（`cache_tbl`）、**LRU → DList**（`lru_dlist`） 管容量與替換
* **v4**：有外送/逾時就引入 **Inflight Map** 與 **Timer Heap**
* **v5**：多 NS 的公平輪替與退避，用 **Ring/List**
* **v6**：CNAME 走訪需要 **Visited Set** 防循環

**練習題**

* 把上面七個 DSA 各用 6–10 字說出「它在 Zone 查詢旅程扮演什麼角色」。

---

## 11) 效能與工程邊角（輕點即可）

* **HashMap 平均 O(1)**；最壞 O(n)（雜湊碰撞）。Python `dict` 內部做了良好工程權衡。
* **記憶體**：大量 zone 會膨脹，真實授權伺服器會用更節省的結構（壓縮 trie、專用索引）。
* **IDNA**：含非 ASCII 的名稱需轉成 punycode，再統一小寫比對（可作為未來練習）。

**練習題**

* 思考：為什麼把「TTL 到期」交給 `ttl_heap` 比在 `ZONE` 裡每次掃描更合理？

---

## 12) 小結：把 Zone 當一個「可交換的模組」

* 對外：只要能「給我 `qname/qtype`，我回 RR 列表」，就合格。
* 對內：今天用 `dict`；明天可換資料庫、可換七件套，**介面不變**。
* 這就是固定資料路徑的威力：`bytes → parse → policy → DSA(core) → policy → encode → bytes`，**核心可熱插拔**。

**練習題**

* 寫一行話描述：固定資料路徑如何讓你敢大膽重構核心而不怕炸外圍。

---

## 附錄：支援多型別的最小 `imports`

在 `server.py` 檔頭補：

```python
from dnslib import DNSRecord, RR, A, AAAA, MX, TXT, QTYPE
```

---

## 收尾 Commit

```bash
git add docs/tutorials/03_zone_as_hashmap.md
git commit -m "docs: add 03_zone_as_hashmap (dict-based zone; multi-type RRSet; TTL notes; exercises)"
```

完成這篇後，你已經把 zone 的概念壓成一個乾淨的 HashMap 介面；接下來只要把 TTL/容量/合併/逾時/輪替/訪問等行為分拆給七個 DSA，整個解析核心會以同一套 API 自然長大。
