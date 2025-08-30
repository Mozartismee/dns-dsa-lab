#!/bin/bash
# push_all.sh
# 建立必要檔案，加入 git，推送到 GitHub

set -e

# 1. 建立 docs 目錄與白皮書檔案
mkdir -p docs
touch docs/concept-api.md

# 2. 建立七個資料結構檔案（若尚未存在則新建空檔）
mkdir -p dns_core/ds
for f in cache_tbl.py ttl_heap.py lru_dlist.py inflight_map.py timer_heap.py ns_ring.py visited_set.py; do
    touch dns_core/ds/$f
done

# 3. 建立測試檔（若尚未存在則新建空檔）
mkdir -p tests
for f in test_cache_tbl.py test_ttl_heap.py test_lru_dlist.py test_inflight_map.py test_timer_heap.py test_ns_ring.py test_visited_set.py; do
    touch tests/$f
done

# 4. Git 操作
git add .
git commit -m "Add concept-api.md and skeleton files for seven DS modules"
git push origin main

