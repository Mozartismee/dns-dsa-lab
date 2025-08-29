
# dns-dsa-lab

在 **macOS** 上以 **Python** 實作的最小 DNS 權威伺服器實驗專案。  
核心目標：把 **網路協議 (DNS)** 與 **資料結構與演算法 (DSA)** 接合，逐步擴充到 Trie/LRU/TTL 與自動化測試。

---

## Features（目前狀態）
- UDP 伺服器，監聽 `127.0.0.1:8053`
- 支援 `A` 記錄查詢
- 內建 zone（範例）：
```

example.lab. → 127.0.0.1  (TTL=60)

````

---

## Requirements
- macOS 12+（Monterey 以上）
- Python 3.10+（建議 3.11/3.12）
- `dig`（macOS 通常已內建；亦可用 `kdig`/`drill`）

---

## Quickstart

### 1) 建立並啟動虛擬環境
```bash
python3 -m venv .venv
source .venv/bin/activate
````

### 2) 安裝依賴

```bash
pip install --upgrade pip
pip install dnslib pytest
```

### 3) 啟動伺服器

```bash
python server.py
# 顯示：DNS server running at 127.0.0.1:8053 ...
```

### 4) 送出查詢（另開一個 Terminal）

```bash
dig @127.0.0.1 -p 8053 example.lab A
```

**預期回覆**

```
;; ANSWER SECTION:
example.lab.   60   IN   A   127.0.0.1
```

---

## Minimal Server（參考程式）

```python
# server.py
from dnslib import DNSRecord, RR, A, QTYPE
import socketserver

ZONE = {"example.lab.": "127.0.0.1"}

class DNSHandler(socketserver.BaseRequestHandler):
    def handle(self):
        data, sock = self.request
        request = DNSRecord.parse(data)

        qname = str(request.q.qname)
        qtype = QTYPE[request.q.qtype]

        reply = request.reply()
        if qname in ZONE and qtype in ("A", "ANY"):
            reply.add_answer(RR(qname, QTYPE.A, rdata=A(ZONE[qname]), ttl=60))

        sock.sendto(reply.pack(), self.client_address)

if __name__ == "__main__":
    server = socketserver.UDPServer(("127.0.0.1", 8053), DNSHandler)
    print("DNS server running at 127.0.0.1:8053 ...")
    server.serve_forever()
```

---

## Project Structure

```
dns-dsa-lab/
├─ .venv/                 # Python 虛擬環境（不要提交到 Git）
├─ server.py              # 最小 DNS 伺服器
└─ README.md
```

---

## Git（可選）

初始化與首次提交：

```bash
git init
echo -e ".venv/\n__pycache__/\n*.pyc\n.DS_Store" > .gitignore
git add .
git commit -m "feat: minimal DNS authoritative server (UDP, A record)"
```

若使用 GitHub：

```bash
git branch -M main
git remote add origin https://github.com/<your-username>/dns-dsa-lab.git
git push -u origin main
```

---

## Roadmap

* **DSA**：以壓縮 Radix Trie 取代 dict；支援最長前綴匹配（LPM）
* **Cache**：TTL + LRU + 負快取（NXDOMAIN/NODATA）
* **Protocol**：CNAME 一跳展開、TCP、EDNS
* **Testing**：pytest 屬性測試（Hypothesis）與端到端測試
* **Observability**：QPS、Cache Hit Ratio、P99 latency

---

## Notes

* 低埠 53 需要 root 權限；本專案先用 **8053** 作為本機實驗埠。
* 若日後需要對外使用 53，可考慮 macOS `pf` 進行 `53 → 8053` 重導以避免提權。

---

```
```
