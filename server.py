from dnslib import DNSRecord, RR, A, QTYPE
import socketserver

# 簡單 zone：只回答 example.lab
ZONE = {
    "example.lab.": "127.0.0.1",
}

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
