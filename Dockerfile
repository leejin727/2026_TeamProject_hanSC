# SubFit 서버를 Railway 같은 리눅스 서버에 올릴 때 쓰는 설정 파일.
# Railway는 저장소 맨 위에 이 파일(Dockerfile)이 있으면 자동으로 이 순서대로 서버를 만든다.
# 내 컴퓨터에서 서버를 켤 때는 쓰지 않는다 (그때는 backend 폴더에서 uvicorn app.main:app --reload).
# API 키와 DB 주소는 이 파일에 적지 않는다. Railway의 Variables 화면에 넣는다.

# 파이썬 3.12가 깔린 리눅스에서 시작한다 (GitHub 자동 검사와 같은 버전)
FROM python:3.12-slim

# 로그를 모았다가 내보내지 않고 바로 내보낸다 (Railway 로그 화면에 바로 보이게)
ENV PYTHONUNBUFFERED=1

WORKDIR /srv

# 패키지 설치. 서버용(backend) + DB에 데이터를 넣는 스크립트용(scripts)
COPY backend/requirements.txt backend/requirements.txt
COPY scripts/requirements.txt scripts/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt -r scripts/requirements.txt

# 서버가 쓰는 폴더만 넣는다. 앱(app/)과 문서(docs/)는 넣지 않는다.
# backend와 data는 저장소에서처럼 나란히 있어야 한다 (서버가 옆의 data 폴더를 읽는다).
COPY backend/ backend/
COPY data/ data/
COPY scripts/ scripts/

WORKDIR /srv/backend

# 켜질 때마다 ① DB에 표를 만들고 노선 데이터를 넣은 뒤 ② 서버를 켠다.
# ①은 여러 번 해도 결과가 같고, 저장된 AI 설명은 건드리지 않는다 (scripts/load_db.py).
# ①이 실패하면(DATABASE_URL이 없거나 틀림) 서버를 켜지 않는다 → 배포 실패로 바로 드러난다.
# 포트는 Railway가 정해 주는 PORT를 쓴다 (없으면 8000).
CMD ["sh", "-c", "python /srv/scripts/load_db.py && exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
