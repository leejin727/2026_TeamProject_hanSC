"""챗봇: 사용자 메시지를 이해하고 답을 만든다. 외부 AI(Gemini)는 부르지 않는다.

- nano/        직접 만든 작은 모델(C++)과 1단계 규칙. nano.understand()가 메시지 하나를 Answer로 바꾼다
- stations.py  문장 속 낱말 → 데이터의 역 (오타·줄임말 포함)
- service.py   Answer → 답 (길찾기는 기존 경로 계산, 나머지는 data/chat/replies.json의 문구)
- settings.py  기준값

API는 app/api/chat.py (POST /chat). 설명: docs/chatbot.md
"""
