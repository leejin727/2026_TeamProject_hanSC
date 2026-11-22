"""챗봇: 사용자 메시지를 이해하고 답을 만든다. 외부 AI(Gemini)는 부르지 않는다.

- nano/        직접 만든 작은 모델(C++)과 1단계 규칙. nano.understand()가 메시지 하나를 Answer로 바꾼다
- stations.py  문장 속 낱말 → 데이터의 역 (오타·줄임말 포함)
- settings.py  기준값

답 만들기(service.py)와 API(POST /chat)는 아직 없다 (다음 단계). 설명: docs/chatbot.md
"""
