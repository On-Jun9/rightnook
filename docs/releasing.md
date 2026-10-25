# 릴리스 절차

첫 공개 기준은 완성된 v1.0.0 소스 한 커밋입니다. 이전 로컬 개발 저장소는 별도로 보존합니다.

`main`은 공개 릴리스, `develop`은 다음 통합 기준입니다. 이후 기능은 `develop`에서 `feature/`, 릴리스는 `release/`, 긴급 수정은 `main`의 `hotfix/`에서 진행합니다. 통합 시 `--no-ff`를 사용합니다. 태그는 검증한 `main` 커밋에 annotated tag로 만들고 기존 태그를 재사용하지 않습니다.

## 배포 전

1. `VERSION`·`BUILD_NUMBER`를 갱신합니다. 빌드 번호는 이전 배포보다 커야 합니다.
2. 새로 clone한 소스에서 테스트·빌드를 실행합니다.
3. 패키지를 생성합니다.

   ```sh
   swift test --scratch-path _build/SwiftPM
   python3 scripts/build.py
   python3 scripts/package.py
   ```

4. `dist/RightNook-<version>.zip`을 별도 폴더에 풀어 서명을 확인하고, 압축을 푼 앱을 설치해 실행합니다.
5. Finder 연결, 여섯 파일 형식 생성과 충돌·취소, 앱으로 열기, Terminal·iTerm2, 설정 적용·재실행을 확인합니다. 기존 파일은 시험 데이터로만 사용합니다.
6. 지원 환경과 실제 검증 범위를 README와 릴리스 노트에 기록합니다. 다른 OS·신규 권한 상태의 미검증을 기존 환경 성공으로 대신하지 않습니다.

## GitHub Release

저장소는 `On-Jun9/rightnook`입니다. 소스와 운영 문서만 Git에 올리고 앱은 Release 첨부로 제공합니다.

- 태그·제목: `v<version>`
- 첨부: `RightNook-<version>.zip`, `SHA256SUMS.txt`
- 본문: 기능·변경점, 설치, 지원 환경, 권한·알려진 제한
- 서명·공증 상태를 명시합니다. 기본 빌드는 ad-hoc이며 Apple 공증을 수행하지 않습니다.

커밋·병합·태그·push·Release 공개는 각각 사용자의 실행 지시 범위 안에서 수행합니다. 준비 작업만으로 자동 공개하지 않습니다.
