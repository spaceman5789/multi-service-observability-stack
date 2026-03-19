from fastapi import FastAPI
from fastapi.responses import JSONResponse, Response
import psycopg2
import redis
import os
import time
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = FastAPI()

# --- Prometheus метрики ---
REQUEST_COUNT = Counter(
    "app_requests_total",
    "Total request count",
    ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "app_request_latency_seconds",
    "Request latency in seconds",
    ["endpoint"]
)

# --- Подключения ---
def get_db():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "postgres"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "appdb"),
        user=os.getenv("DB_USER", "appuser"),
        password=os.getenv("DB_PASSWORD", "apppass"),
    )

def get_redis():
    return redis.Redis(
        host=os.getenv("REDIS_HOST", "redis"),
        port=int(os.getenv("REDIS_PORT", "6379")),
        decode_responses=True,
    )

# --- Инициализация таблицы ---
@app.on_event("startup")
def startup():
    # Ждём пока БД поднимется
    for i in range(10):
        try:
            conn = get_db()
            cur = conn.cursor()
            cur.execute("""
                CREATE TABLE IF NOT EXISTS visits (
                    id SERIAL PRIMARY KEY,
                    timestamp TIMESTAMPTZ DEFAULT NOW()
                )
            """)
            conn.commit()
            cur.close()
            conn.close()
            print("DB ready")
            break
        except Exception as e:
            print(f"Waiting for DB... ({e})")
            time.sleep(2)

# --- Эндпоинты ---
@app.get("/")
def root():
    start = time.time()

    conn = get_db()
    cur = conn.cursor()
    cur.execute("INSERT INTO visits DEFAULT VALUES")
    conn.commit()

    r = get_redis()
    count = r.incr("visit_count")

    cur.execute("SELECT COUNT(*) FROM visits")
    db_count = cur.fetchone()[0]
    cur.close()
    conn.close()

    REQUEST_COUNT.labels("GET", "/", "200").inc()
    REQUEST_LATENCY.labels("/").observe(time.time() - start)

    return {
        "message": "Hello from the API!",
        "visits_redis": count,
        "visits_db": db_count,
    }

@app.get("/health")
def health():
    REQUEST_COUNT.labels("GET", "/health", "200").inc()
    return {"status": "healthy"}

@app.get("/metrics")
def metrics():
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST,
    )
