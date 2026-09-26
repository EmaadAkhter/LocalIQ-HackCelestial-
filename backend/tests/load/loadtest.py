"""Lightweight concurrency/load check for the LocalIQ API.

No extra dependencies — uses httpx (already required) and asyncio.

Examples:
    # Local edge
    python tests/load/loadtest.py --base http://localhost:8080

    # Public tunnel
    python tests/load/loadtest.py --base https://localiq.tavesglobal.com --requests 300 --concurrency 30
"""

from __future__ import annotations

import argparse
import asyncio
import statistics
import time

import httpx

ENDPOINTS = [
    ("GET", "/healthz"),
    ("GET", "/api/v1/experiences?limit=10"),
    ("POST", "/api/v1/recommend"),
]

RECOMMEND_BODY = {
    "location": "Bandra",
    "time_hours": 4,
    "budget_inr": 1500,
    "interests": ["food"],
    "limit": 10,
}


def _percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, int(round((pct / 100) * (len(ordered) - 1))))
    return ordered[index]


async def _one(client: httpx.AsyncClient, method: str, path: str) -> tuple[int, float]:
    start = time.perf_counter()
    try:
        if method == "POST":
            response = await client.post(path, json=RECOMMEND_BODY)
        else:
            response = await client.get(path)
        return response.status_code, time.perf_counter() - start
    except Exception:
        return 0, time.perf_counter() - start


async def _run(base: str, requests: int, concurrency: int) -> None:
    async with httpx.AsyncClient(base_url=base, timeout=30.0) as client:
        for method, path in ENDPOINTS:
            semaphore = asyncio.Semaphore(concurrency)
            results: list[tuple[int, float]] = []

            async def worker() -> None:
                async with semaphore:
                    results.append(await _one(client, method, path))

            await asyncio.gather(*(worker() for _ in range(requests)))

            codes: dict[int, int] = {}
            for status, _ in results:
                codes[status] = codes.get(status, 0) + 1
            latencies = [latency for _, latency in results]
            print(f"{method:4} {path}")
            print(f"     status: {dict(sorted(codes.items()))}")
            print(
                f"     latency ms  p50={_percentile(latencies, 50) * 1000:.1f} "
                f"p95={_percentile(latencies, 95) * 1000:.1f} "
                f"max={max(latencies) * 1000:.1f} "
                f"mean={statistics.mean(latencies) * 1000:.1f}"
            )


def main() -> None:
    parser = argparse.ArgumentParser(description="LocalIQ load check")
    parser.add_argument("--base", default="http://localhost:8080")
    parser.add_argument("--requests", type=int, default=100)
    parser.add_argument("--concurrency", type=int, default=10)
    args = parser.parse_args()

    print(f"Target {args.base} | requests={args.requests} concurrency={args.concurrency}\n")
    asyncio.run(_run(args.base, args.requests, args.concurrency))


if __name__ == "__main__":
    main()
