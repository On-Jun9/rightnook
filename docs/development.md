# 개발 안내

## 빌드

Apple Silicon Mac, Xcode, Python 3가 필요합니다. 네이티브 빌드는 `xcrun swiftc`로 본체·Finder 확장·파일 생성 도우미를 컴파일합니다. Swift 5 언어 모드, `arm64-apple-macosx14.0` 타깃입니다. 검증 도구는 Xcode 27.0·Swift 6.4입니다.

```sh
python3 scripts/build.py
python3 scripts/install.py
swift test --scratch-path _build/SwiftPM
```

`VERSION`과 `BUILD_NUMBER`가 세 번들의 버전·빌드 번호를 결정합니다. UI 버전은 실행 중인 번들의 Info.plist에서 읽습니다. 빌드할 때 번호를 자동 증가시키지 않습니다.

`_build/Release/RightNook.app`에 완성된 앱이 생성됩니다. `Config/`의 Info.plist·entitlements는 빌드가 생성합니다. 서명은 기본적으로 ad-hoc이며 `--identity` 또는 `RIGHTNOOK_SIGN_IDENTITY`로 지정할 수 있습니다. 서명 identity 지정만으로 공증이 수행되지는 않습니다.

아이콘 원본은 `Resources/RightNook.svg`, 번들 아이콘은 `Resources/RightNook.icns`입니다. `xcrun swift scripts/make_icon.swift`로 PNG·ICNS를 다시 생성합니다.

## 코드 구조

| 위치 | 책임 |
| --- | --- |
| `Sources/Core` | 설정·요청 검증, 파일·폴더 문맥, 덮어쓰기 방지 생성, 기본 문서 |
| `Sources/Host` | 설정 UI, 앱 등록, URL 수신과 외부 앱 열기 |
| `Sources/Finder` | FinderSync 메뉴 생성과 본체·도우미 호출 |
| `Sources/FileCreator` | 독립 저장창과 실제 파일 생성 |
| `Tests` | 공유 로직의 XCTest |
| `scripts` | 빌드·설치·패키지와 기본 문서·아이콘 생성 |

본체는 비샌드박스, Finder 확장과 생성 도우미는 샌드박스입니다. 메뉴 전용 JSON 디렉터리에만 읽기 예외를 둡니다. App Group은 사용하지 않습니다. 폴더 bookmark는 전체 설정에만 저장하고 메뉴 스냅샷에 넣지 않습니다.

Finder 명령은 정수 tag로 문맥을 캡처합니다. 본체·도우미는 요청 버전·URL·대상 수와 현재 활성 상태를 다시 검사합니다. 앱 열기는 등록 UUID를 확인하고 명시한 앱 URL의 `NSWorkspace.open`을 사용합니다. 셸 문자열로 사용자 경로를 실행하지 않습니다.

기존 로컬판의 설정을 유지하려고 bundle ID `local.hj.quickright`와 하위 ID, `quickright`·`quickright-file` URL scheme, QuickRight 설정 경로·창 복원 키를 유지합니다. 표시 이름은 RightNook입니다. 복제 프로젝트의 독립 앱을 배포한다면 이 식별자와 저장 경로를 함께 변경해야 합니다.

## 기본 문서

RTF·DOCX·XLSX·PPTX는 직접 생성한 빈 문서입니다. 기존 앱의 바이너리·아이콘·문서를 포함하지 않습니다. 일반 빌드는 저장소의 기본 문서를 복사하므로 외부 Python 패키지가 필요하지 않습니다.

생성 후 썸네일·프린터 설정·사용자 정의 XML과 해당 관계를 제거하고, 작성자 등 문서 속성을 비웁니다. `verify`는 ZIP·XML·관계, 불필요한 바이너리 부품과 문서 속성도 검사합니다. 배포 자료의 출처는 [개인정보와 배포 자료](privacy-and-licenses.md)에 있습니다.

다시 생성하거나 구조를 검사할 때만 별도 환경에서 다음 패키지를 사용합니다.

```sh
python3 -m venv _build/template-venv
_build/template-venv/bin/pip install python-docx==1.2.0 openpyxl==3.1.5 python-pptx==1.0.2
_build/template-venv/bin/python scripts/file_templates.py generate
_build/template-venv/bin/python scripts/file_templates.py verify
```

Python 런타임은 앱에 포함하지 않습니다. 관련 고지는 `THIRD_PARTY_NOTICES.txt`에 보존합니다.

## 변경 시 확인

공유 로직 변경은 XCTest를 실행합니다. Finder 명령·저장창·외부 앱 호출·권한 변경은 실제 설치본으로도 확인합니다. 새 파일은 기존 이름 충돌과 최종 덮어쓰기 거부를 유지해야 합니다. 개인 설정·로그·bookmark·서명 자료는 저장소에 넣지 않습니다.
