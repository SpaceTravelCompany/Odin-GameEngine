#!/usr/bin/env python3
"""
간단한 Python 웹서버
bin 디렉토리의 정적 파일들을 서빙합니다.
"""

import http.server
import socketserver
import os
import sys
from pathlib import Path

# bin 디렉토리 경로
BIN_DIR = Path(__file__).parent
PORT = 8000

def main():
    # bin 디렉토리가 존재하는지 확인
    if not BIN_DIR.exists():
        print(f"오류: {BIN_DIR} 디렉토리를 찾을 수 없습니다.")
        sys.exit(1)
    
    # bin 디렉토리로 이동
    os.chdir(BIN_DIR)
    
    # HTTP 서버 생성
    Handler = http.server.SimpleHTTPRequestHandler
    
    try:
        with socketserver.TCPServer(("", PORT), Handler) as httpd:
            print(f"웹서버가 시작되었습니다!")
            print(f"브라우저에서 http://localhost:{PORT} 를 열어주세요.")
            httpd.serve_forever()
    except OSError as e:
        if e.errno == 98 or e.errno == 10048:  # Address already in use
            print(f"오류: 포트 {PORT}가 이미 사용 중입니다.")
            print(f"다른 포트를 사용하려면 스크립트를 수정하세요.")
        else:
            print(f"오류: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
