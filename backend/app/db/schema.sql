-- SubFit DB 테이블 정의 (PostgreSQL). 설명은 docs/db-schema.md
--
-- scripts/load_db.py가 실행될 때마다 이 파일을 먼저 실행한다.
-- IF NOT EXISTS: 테이블이 이미 있으면 그대로 둔다 (안의 데이터도 그대로).
-- 그래서 이미 만든 테이블의 컬럼을 여기서 바꿔도 DB에는 자동으로 반영되지 않는다.
-- 바꾸는 방법은 docs/db-schema.md "테이블 모양을 바꿀 때"를 본다.


-- 1. 노선 (data/extra/lines.csv)
CREATE TABLE IF NOT EXISTS lines (
    line        INTEGER PRIMARY KEY,     -- 노선 번호
    is_circular BOOLEAN NOT NULL         -- 순환선이면 true (1·6호선)
);

-- 2. 역 (원본 stations.xlsx에 나오는 역 전체)
--    ID만 있는 기준표. 다른 표들이 "실제로 있는 역인지" 확인할 때 이 표를 가리킨다.
CREATE TABLE IF NOT EXISTS stations (
    id TEXT PRIMARY KEY                  -- 예: '101'. 역 번호는 이름표라 문자열로 다룬다
);

-- 3. 역 이름 (data/extra/station_names.csv) — 역 × 언어마다 한 행
CREATE TABLE IF NOT EXISTS station_names (
    station_id TEXT NOT NULL REFERENCES stations (id),
    lang       TEXT NOT NULL,            -- 'ko', 'en'
    name       TEXT NOT NULL,
    PRIMARY KEY (station_id, lang),
    UNIQUE (lang, name)                  -- 같은 언어 안에서 역 이름이 겹치지 않게
);

-- 4. 노선별 역 순서 (data/extra/line_stations.csv)
--    역 번호 앞자리로 노선을 추정하지 않고, 항상 이 표로 노선을 판단한다.
CREATE TABLE IF NOT EXISTS line_stations (
    line       INTEGER NOT NULL REFERENCES lines (line),
    seq        INTEGER NOT NULL CHECK (seq >= 1),   -- 노선 안에서의 순서 (1부터)
    station_id TEXT    NOT NULL REFERENCES stations (id),
    PRIMARY KEY (line, seq),
    UNIQUE (line, station_id)            -- 한 노선에 같은 역이 두 번 나오지 않게
);

-- 5. 구간 (원본 data/raw/stations.xlsx 그대로)
--    양방향이고 두 방향 값이 같아서 한 번만 저장한다. 작은 ID를 station_a에 둔다.
CREATE TABLE IF NOT EXISTS edges (
    station_a  TEXT    NOT NULL REFERENCES stations (id),
    station_b  TEXT    NOT NULL REFERENCES stations (id),
    travel_sec INTEGER NOT NULL CHECK (travel_sec > 0),   -- 원본 "시간(초)"
    distance_m INTEGER NOT NULL CHECK (distance_m > 0),   -- 원본 "거리(미터)". API 응답에는 넣지 않는다
    cost_won   INTEGER NOT NULL CHECK (cost_won > 0),     -- 원본 "비용(원)". 실제 지하철 요금 아님
    PRIMARY KEY (station_a, station_b),
    CHECK (station_a < station_b)
);

-- 6. 환승 (data/extra/transfers.csv) — 환승역 × 노선 쌍마다 한 행
CREATE TABLE IF NOT EXISTS transfers (
    station_id   TEXT    NOT NULL,
    line_a       INTEGER NOT NULL,       -- 작은 노선 번호
    line_b       INTEGER NOT NULL,       -- 큰 노선 번호
    transfer_sec INTEGER NOT NULL CHECK (transfer_sec > 0),
    PRIMARY KEY (station_id, line_a, line_b),
    CHECK (line_a < line_b),
    -- 환승역이 두 노선 모두에 정말 있는지 DB가 직접 검사한다
    FOREIGN KEY (line_a, station_id) REFERENCES line_stations (line, station_id),
    FOREIGN KEY (line_b, station_id) REFERENCES line_stations (line, station_id)
);

-- 7. 주변 인프라 — 데이터를 어디서 가져올지 정해질 때까지 비어 있다 (api-spec 논의 필요 4)
--    load_db.py는 이 표를 건드리지 않는다.
CREATE TABLE IF NOT EXISTS nearby_facilities (
    id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,  -- 1, 2, 3 … 자동 번호
    station_id TEXT NOT NULL REFERENCES stations (id),
    category   TEXT NOT NULL CHECK (category IN ('cafe', 'restaurant', 'convenience_store', 'activity')),
    name_ko    TEXT NOT NULL,
    name_en    TEXT NOT NULL
);

-- 8. AI 설명 캐시 — POST /explain이 채운다. load_db.py는 이 표를 건드리지 않는다.
--    같은 cache_key + 같은 lang이면 Gemini를 다시 부르지 않고 저장된 text를 쓴다.
CREATE TABLE IF NOT EXISTS ai_explanations (
    cache_key  TEXT        NOT NULL,     -- 어떤 경로·모임역 결과에 대한 설명인지. 만드는 방법은 /explain 구현 때 정한다 (논의 필요 8)
    lang       TEXT        NOT NULL,     -- 설명 언어 (en, ko, ja …)
    type       TEXT        NOT NULL CHECK (type IN ('route', 'meeting')),
    text       TEXT        NOT NULL,     -- Gemini가 만든 설명 문장
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (cache_key, lang)
);

-- 9. 주변 시설 AI 예시 캐시 — GET /stations/{id}/facilities가 채운다. load_db.py는 이 표를 건드리지 않는다.
--    실제 데이터가 아니라 역 이름을 바탕으로 AI가 만든 예시다 (ASSUMPTIONS.md 팀 결정 2026-11-18).
--    위 7번 nearby_facilities(실제 데이터용, 비어 있음)와는 다른 표다.
--    같은 역 + 같은 언어면 Gemini를 다시 부르지 않고 저장된 items를 쓴다 → 같은 역은 늘 같은 시설이 보인다.
CREATE TABLE IF NOT EXISTS ai_facilities (
    station_id TEXT        NOT NULL,     -- 역 ID (예: '705')
    lang       TEXT        NOT NULL,     -- 시설 이름·위치 안내 언어 (ko, en, ja …)
    items      JSONB       NOT NULL,     -- [{"category", "name", "detail"}, …] 최대 5개
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (station_id, lang)
);
