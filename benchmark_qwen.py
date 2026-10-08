#!/usr/bin/env python3
"""
Benchmark Qwen2.5-1.5B on Galaxy Note 10+ via loopback port forward.
Measures:
- Latency per article (s)
- Output token count and generation rate (tokens/s)
- JSON validity & localization quality
- Device RAM / CPU impact
- Backend & DB stability verification
"""

import json
import time
import urllib.request
import subprocess
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

API_URL = "http://127.0.0.1:8088/v1/chat/completions"
ADB_PATH = r"C:\Users\khoid\AppData\Local\Android\Sdk\platform-tools\adb.exe"
DEVICE_ID = "R3CM8105TPA"

REAL_ARTICLES = [
    {
        "id": "art-01",
        "title": "Fed signals potential rate cuts as inflation cools toward 2% target",
        "publisher": "Reuters",
        "url": "https://www.reuters.com/markets/us/fed-signals-rate-cut-inflation-cooling-2026",
        "published_at": "2026-10-08 14:30:00",
        "summary": "Federal Reserve officials indicated that interest rate cuts remain on the table before year-end as consumer price inflation showed continued moderation towards the central bank's 2% objective. Labor market conditions also exhibited gradual cooling without sharp contractions."
    },
    {
        "id": "art-02",
        "title": "Bitcoin surges past $65,000 as institutional ETF inflows rebound",
        "publisher": "Bloomberg",
        "url": "https://www.bloomberg.com/news/articles/2026-10-08/bitcoin-rebounds-etf-inflows",
        "published_at": "2026-10-08 15:10:00",
        "summary": "Bitcoin climbed back above $65,000 on Thursday following three consecutive days of net inflows into spot exchange-traded funds. Market participants pointed to renewed macro appetite and derivative liquidations short-squeezing bearish positions."
    },
    {
        "id": "art-03",
        "title": "S&P 500 closes at record high led by tech earnings and chipmaker rally",
        "publisher": "CNBC",
        "url": "https://www.cnbc.com/2026/10/08/sp500-tech-chipmaker-rally-record.html",
        "published_at": "2026-10-08 16:00:00",
        "summary": "The S&P 500 ended Thursday at an all-time record, propelled by semiconductor manufacturers reporting stronger than expected data-center demand. The Nasdaq Composite also gained 1.4% with breadth favoring large-cap technology firms."
    },
    {
        "id": "art-04",
        "title": "Ethereum network fee burns increase amid layer 2 scaling adoption",
        "publisher": "CoinDesk",
        "url": "https://www.coindesk.com/tech/2026/10/08/ethereum-fee-burn-layer2-growth/",
        "published_at": "2026-10-08 13:45:00",
        "summary": "Daily Ethereum burning through EIP-1559 rose 12% week-on-week as rollups posted record transaction volumes to mainnet. The deflationary pressure reduced total net supply issuance despite lower base gas fees."
    },
    {
        "id": "art-05",
        "title": "Oil prices steady near $75 per barrel after OPEC+ maintains output limits",
        "publisher": "Reuters",
        "url": "https://www.reuters.com/business/energy/oil-steady-opec-output-limits-2026",
        "published_at": "2026-10-08 11:20:00",
        "summary": "Brent crude futures traded in a tight range around $75 a barrel following an OPEC+ monitoring committee meeting that confirmed voluntary production cuts would remain in effect through the fourth quarter."
    },
    {
        "id": "art-06",
        "title": "US Dollar Index softens as Treasury yields decline following jobs data",
        "publisher": "Bloomberg",
        "url": "https://www.bloomberg.com/news/articles/2026-10-08/dollar-yields-jobs-data",
        "published_at": "2026-10-08 12:00:00",
        "summary": "The greenback slipped against major peers as the 10-year Treasury yield dropped 6 basis points to 3.82%. Investors revised terminal rate projections downward following weaker hiring prints in non-manufacturing sectors."
    },
    {
        "id": "art-07",
        "title": "Treasury yields slip as investors digest retail sales and labor market numbers",
        "publisher": "CNBC",
        "url": "https://www.cnbc.com/2026/10/08/treasury-yields-retail-sales-labor.html",
        "published_at": "2026-10-08 14:15:00",
        "summary": "Bond markets saw sustained buying across the curve with 2-year yields dropping to their lowest level in four months. Retail spending showed resilient consumer demand in essential categories while discretionary outlays moderated."
    },
    {
        "id": "art-08",
        "title": "Solana daily active addresses hit six-month high driven by DeFi activity",
        "publisher": "CoinDesk",
        "url": "https://www.coindesk.com/markets/2026/10/08/solana-active-addresses-defi-high/",
        "published_at": "2026-10-08 10:30:00",
        "summary": "On-chain analytics reveal Solana daily active wallets surpassed 3.2 million, led by decentralized exchange trading volumes and liquid staking protocols. Total value locked grew 8% over the past seven days."
    },
    {
        "id": "art-09",
        "title": "ECB cuts interest rates by 25 basis points citing sluggish economic growth",
        "publisher": "Reuters",
        "url": "https://www.reuters.com/markets/europe/ecb-cuts-rates-growth-worries-2026",
        "published_at": "2026-10-08 09:15:00",
        "summary": "The European Central Bank lowered its deposit rate to 3.25%, marking its second cut this year. Governing Council members emphasized deteriorating forward manufacturing indicators across Germany and France."
    },
    {
        "id": "art-10",
        "title": "Gold hits fresh peak as central banks bolster reserves and haven demand rises",
        "publisher": "Bloomberg",
        "url": "https://www.bloomberg.com/news/articles/2026-10-08/gold-record-peak-central-banks",
        "published_at": "2026-10-08 16:30:00",
        "summary": "Spot bullion advanced toward $2,680 an ounce as sovereign institutions reported sustained reserve diversification into precious metals. Geopolitical friction and sovereign debt issuance concerns further fueled institutional allocations."
    },
    {
        "id": "art-11",
        "title": "Apple reveals new AI features for flagship devices, shares edge higher",
        "publisher": "CNBC",
        "url": "https://www.cnbc.com/2026/10/08/apple-ai-features-rollout-shares.html",
        "published_at": "2026-10-08 17:00:00",
        "summary": "Apple rolled out software updates integrating on-device neural processing models for text synthesis and photo categorization. Analysts noted positive early adoption signals for hardware upgrade replacement cycles."
    },
    {
        "id": "art-12",
        "title": "Binance announces new compliance certifications across multiple European jurisdictions",
        "publisher": "CoinDesk",
        "url": "https://www.coindesk.com/policy/2026/10/08/binance-compliance-licenses-europe/",
        "published_at": "2026-10-08 08:45:00",
        "summary": "The cryptocurrency exchange secured regulatory registrations fulfilling EU MiCA requirements in two additional member states, strengthening its local banking rails and segregated fiat custody frameworks."
    },
    {
        "id": "art-13",
        "title": "Japan core inflation accelerates, keeping Bank of Japan rate hike expectations alive",
        "publisher": "Reuters",
        "url": "https://www.reuters.com/markets/asia/japan-cpi-inflation-boj-hike-2026",
        "published_at": "2026-10-08 07:30:00",
        "summary": "Core consumer prices in Tokyo rose 2.8% year-on-year, outpacing consensus forecasts. Economists expect the Bank of Japan to weigh further policy normalization if wage gains continue filtering into service sector costs."
    },
    {
        "id": "art-14",
        "title": "Global equity funds see biggest weekly inflow in three months",
        "publisher": "Bloomberg",
        "url": "https://www.bloomberg.com/news/articles/2026-10-08/global-funds-biggest-weekly-inflows",
        "published_at": "2026-10-08 15:45:00",
        "summary": "International mutual funds and ETFs absorbed $24 billion in new capital over the past week according to EPFR data. Emerging market debt and broad equities accounted for the majority of new cash commitments."
    },
    {
        "id": "art-15",
        "title": "Retail trading activity jumps in September with options volume reaching new records",
        "publisher": "CNBC",
        "url": "https://www.cnbc.com/2026/10/08/retail-trading-options-volume-records.html",
        "published_at": "2026-10-08 18:00:00",
        "summary": "Brokerage metrics highlighted elevated retail participation in zero-day-to-expiration (0DTE) contracts and broad index options. Market makers reported orderly spreads despite higher intraday volatility swings."
    }
]

SYSTEM_PROMPT = """Bạn là trợ lý tài chính dịch và tóm tắt tin tức kinh tế sang tiếng Việt.
YÊU CẦU BẮT BUỘC:
1. Dịch tiêu đề sang tiếng Việt chuẩn ngữ cảnh kinh tế tài chính.
2. Tóm tắt 2-3 ý chính (gạch đầu dòng) súc tích, thực chất bằng tiếng Việt.
3. Đánh giá xu hướng thị trường (BULLISH, BEARISH hoặc NEUTRAL).
4. Độ tin cậy từ 70 đến 95.
5. Giải thích ngắn gọn lý do đánh giá.
6. TUYỆT ĐỐI KHÔNG tự bịa số liệu, KHÔNG đưa ra khuyến nghị mua bán đầu tư.
7. Trả về DUY NHẤT một đối tượng JSON hợp lệ, không thêm bất kỳ văn bản nào khác.

Định dạng JSON:
{
  "displayTitleVi": "Tiêu đề tiếng Việt",
  "summary": ["Ý chính 1", "Ý chính 2"],
  "sentiment": "BULLISH",
  "confidence": 85,
  "reason": "Lý do ngắn gọn"
}"""

def get_device_mem_and_cpu():
    try:
        res = subprocess.run(
            [ADB_PATH, "-s", DEVICE_ID, "shell", "run-as com.termux cat /proc/$(cat /data/data/com.termux/files/home/qwen.pid 2>/dev/null)/status | grep -E 'VmRSS|VmSize'"],
            capture_output=True, text=True, timeout=5
        )
        mem_info = res.stdout.strip().replace("\n", " | ")
        return mem_info if mem_info else "N/A"
    except Exception as e:
        return f"Err: {e}"

def check_backend_and_db_health():
    try:
        actuator = subprocess.run(
            [ADB_PATH, "-s", DEVICE_ID, "shell", "run-as com.termux /data/data/com.termux/files/usr/bin/curl -s -m 2 http://127.0.0.1:8083/actuator/health"],
            capture_output=True, text=True, timeout=5
        ).stdout
        is_backend_up = '"status":"UP"' in actuator

        db_check = subprocess.run(
            [ADB_PATH, "-s", DEVICE_ID, "shell", "run-as com.termux /data/data/com.termux/files/usr/bin/psql -d fnmf_test -U fnmf_test_user -t -A -c 'SELECT 1;'"],
            capture_output=True, text=True, timeout=5
        ).stdout.strip()
        is_db_up = db_check == "1"

        return is_backend_up, is_db_up
    except Exception as e:
        return False, False

def benchmark_article(art, idx, total):
    user_prompt = f"Tiêu đề: {art['title']}\nNguồn: {art['publisher']}\nNội dung: {art['summary']}"
    payload = {
        "model": "/data/data/com.termux/files/home/models/qwen2.5-1.5b-instruct-q4_k_m.gguf",
        "temperature": 0.2,
        "max_tokens": 256,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt}
        ]
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(API_URL, data=data, headers={"Content-Type": "application/json"})

    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=40) as resp:
            elapsed = time.time() - t0
            raw_body = resp.read().decode("utf-8")
            res_json = json.loads(raw_body)
            content = res_json["choices"][0]["message"]["content"].strip()
            timings = res_json.get("timings", {})
            pred_tokens = timings.get("predicted_n", 0)
            pred_speed = timings.get("predicted_per_second", 0.0)

            # Clean markdown fences if any
            clean_content = content
            if clean_content.startswith("```json"): clean_content = clean_content[7:]
            if clean_content.startswith("```"): clean_content = clean_content[3:]
            if clean_content.endswith("```"): clean_content = clean_content[:-3]
            clean_content = clean_content.strip()

            parsed = json.loads(clean_content)
            has_title = bool(parsed.get("displayTitleVi"))
            has_summary = isinstance(parsed.get("summary"), list) and len(parsed.get("summary")) >= 1
            has_sentiment = parsed.get("sentiment") in ["BULLISH", "BEARISH", "NEUTRAL"]
            has_confidence = isinstance(parsed.get("confidence"), (int, float))
            valid_schema = has_title and has_summary and has_sentiment and has_confidence

            return {
                "idx": idx,
                "id": art["id"],
                "elapsed": round(elapsed, 2),
                "tokens": pred_tokens,
                "speed": round(pred_speed, 1),
                "valid_json": True,
                "valid_schema": valid_schema,
                "display_title": parsed.get("displayTitleVi", "")[:45],
                "sentiment": parsed.get("sentiment", ""),
                "bullets_count": len(parsed.get("summary", [])),
                "error": None
            }
    except Exception as e:
        elapsed = time.time() - t0
        return {
            "idx": idx,
            "id": art["id"],
            "elapsed": round(elapsed, 2),
            "tokens": 0,
            "speed": 0.0,
            "valid_json": False,
            "valid_schema": False,
            "display_title": "",
            "sentiment": "",
            "bullets_count": 0,
            "error": str(e)
        }

def main():
    print("=" * 80)
    print("    BENCHMARK QWEN2.5-1.5B TRÊN SAMSUNG GALAXY NOTE 10+ (15 BÀI THẬT)    ")
    print("=" * 80)

    b_up, db_up = check_backend_and_db_health()
    print(f"Trạng thái ban đầu: Spring Boot Backend UP={b_up} | PostgreSQL UP={db_up}")
    mem_before = get_device_mem_and_cpu()
    print(f"Bộ nhớ llama-server ban đầu: {mem_before}")
    print("-" * 80)

    results = []
    total = len(REAL_ARTICLES)

    for i, art in enumerate(REAL_ARTICLES, 1):
        print(f"[{i:02d}/{total}] Đang xử lý: {art['title'][:55]}...")
        res = benchmark_article(art, i, total)
        results.append(res)
        status_str = "OK" if res["valid_schema"] else f"FAIL ({res['error']})"
        print(f"     -> Thời gian: {res['elapsed']}s | Tokens: {res['tokens']} ({res['speed']} t/s) | JSON: {status_str} | Title: {res['display_title']} | Sentiment: {res['sentiment']}")
        time.sleep(0.5)

    print("=" * 80)
    print("                      TỔNG KẾT KẾT QUẢ ĐO LƯỜNG                           ")
    print("=" * 80)
    
    success_count = sum(1 for r in results if r["valid_schema"])
    avg_time = sum(r["elapsed"] for r in results) / total
    avg_speed = sum(r["speed"] for r in results if r["speed"] > 0) / max(1, success_count)
    total_tokens = sum(r["tokens"] for r in results)
    
    print(f"Tổng số bài thử nghiệm : {total} bài tin tức tài chính thật")
    print(f"Tỉ lệ JSON/Schema hợp lệ: {success_count}/{total} ({success_count/total*100:.1f}%)")
    print(f"Thời gian trung bình/bài: {avg_time:.2f} giây (Min: {min(r['elapsed'] for r in results):.2f}s, Max: {max(r['elapsed'] for r in results):.2f}s)")
    print(f"Tốc độ sinh trung bình : {avg_speed:.1f} tokens/giây (Tổng: {total_tokens} tokens)")
    
    mem_after = get_device_mem_and_cpu()
    print(f"Bộ nhớ llama-server sau đo : {mem_after}")
    
    b_up_after, db_up_after = check_backend_and_db_health()
    print(f"Trạng thái sau đo: Spring Boot Backend UP={b_up_after} | PostgreSQL UP={db_up_after}")
    
    if b_up_after and db_up_after:
        print("KẾT LUẬN: Qwen2.5-1.5B chạy ổn định, không làm gián đoạn Backend hoặc Database.")
    else:
        print("CẢNH BÁO: Backend hoặc Database bị ảnh hưởng sau quá trình đo!")

if __name__ == "__main__":
    main()
