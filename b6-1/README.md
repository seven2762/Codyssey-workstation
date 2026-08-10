# B6-1 클라우드 인프라 구축 미션

VPC로 격리된 네트워크를 직접 설계하고, EC2에 웹 서버를 배포해 외부에서 접속 가능한 서비스 환경을 구성했다. 보안 그룹과 IAM 최소권한을 적용하고, 발생한 오류는 로그를 근거로 분석해 해결했다.

- **리전**: ap-northeast-2 (서울)
- **작업일**: 2026-08-10
- **아키텍처 다이어그램**: [`docs/architecture.png`](docs/architecture.png)

---

## 1. 외부 접속 검증

**선택한 방식: (A) 브라우저 접속**

| 항목 | 값 |
| --- | --- |
| 접속 URL | `http://15.165.74.3` |
| 기대 결과 | Nginx 기본 페이지 정상 표시 (HTTP 200) |
| 증빙 | `docs/images/05-browser-access.png` |

`(B) /health` 방식은 선택하지 않았다. 서버 1대 구성이라 로드밸런서·오케스트레이터가 주기적으로 호출할 대상이 없고, 요구사항이 택 1이므로 (A)로 검증했다.

---

## 2. 구성 리소스

| 구분 | 이름 / ID | 설정값 |
| --- | --- | --- |
| VPC | codyssey / `vpc-0022a01e987ae669a` | `10.0.0.0/16` |
| Public Subnet | cody-subnet | `10.0.1.0/24`, ap-northeast-2a, 퍼블릭 IP 자동 할당 ON |
| Internet Gateway | cody-gateway | VPC에 Attached |
| Route Table | cody-route | `10.0.0.0/16 → local`, `0.0.0.0/0 → igw` (Active), 서브넷 명시적 연결 |
| EC2 | cody-server | t3.micro, Amazon Linux 2023, Private `10.0.1.224`, Public `15.165.74.3` |
| 웹 서버 | Nginx 1.30.4 | active (running), 부팅 시 자동 시작 설정(`systemctl enable`) |
| Security Group | cody-web-sg | 인바운드 TCP 22 (My IP), TCP 80 (0.0.0.0/0) |
| IAM 사용자 | cody-iam | AmazonEC2FullAccess |

### 라우팅 테이블을 별도로 생성한 이유

VPC 생성 시 자동으로 만들어지는 메인 라우팅 테이블을 수정하지 않고, 퍼블릭 전용 라우팅 테이블을 새로 만들어 서브넷에 명시적으로 연결했다.

메인 라우팅 테이블에 `0.0.0.0/0 → IGW`를 넣으면, 이후 이 VPC에 추가되는 모든 서브넷이 명시적 연결이 없는 한 그 경로를 자동으로 상속한다. 프라이빗 서브넷을 추가하면서 연결을 누락하면 의도치 않게 인터넷에 노출되는 서브넷이 생긴다. 퍼블릭 경로를 별도 테이블로 분리해두면 "연결한 서브넷만 퍼블릭"이 되어 이 사고를 구조적으로 막을 수 있다.

---

## 3. 검증 결과

| 검증 항목 | 명령 / 방법 | 결과 | 증빙 |
| --- | --- | --- | --- |
| 인스턴스 상태 | EC2 콘솔 | 실행 중, 상태 검사 3/3 통과 | `01-instance-list.png` |
| 아웃바운드 통신 | `curl -I https://example.com` | `HTTP/2 200` | `02-outbound-curl.png` |
| 웹 서버 로컬 응답 | `curl -I http://localhost` | `HTTP/1.1 200 OK`, `Server: nginx/1.30.4` | `03-localhost-curl.png` |
| 외부 접속 | 브라우저 `http://15.165.74.3` | Nginx 기본 페이지 표시 | `05-browser-access.png` |
| 보안 그룹 인바운드 | EC2 → 보안 탭 | SSH 22 → `/32` 단일 IP, HTTP 80 → `0.0.0.0/0` | `06-security-group.png` |
| 최소권한 (허용) | IAM 사용자로 EC2 콘솔 조회 | 인스턴스 정상 조회 | `01-instance-list.png` |
| 최소권한 (차단) | IAM 사용자로 S3 콘솔 조회 | `s3:ListAllMyBuckets` 권한 없음 오류 | `04-s3-denied.png` |

아웃바운드 확인 시 셸 프롬프트가 `[ec2-user@ip-10-0-1-224 ~]$`로 표시되어, 인스턴스가 `10.0.1.0/24` 서브넷에 배치되었음을 함께 확인할 수 있다.

---

## 4. 보안 설계

### Security Group과 IAM의 역할 구분

두 가지는 통제 대상이 다르다.

| | Security Group | IAM |
| --- | --- | --- |
| 통제 대상 | 네트워크 패킷 | 사람 / 애플리케이션의 API 호출 |
| 동작 계층 | 데이터 평면 (인스턴스 앞단 방화벽) | 관리 평면 (콘솔 / API) |
| 적용 예 | 22번 포트는 특정 IP만 통과 | 이 사용자는 EC2는 되고 S3는 안 됨 |

Security Group은 서버로 들어오는 트래픽을 걸러내고, IAM은 AWS 리소스 자체를 조작할 권한을 통제한다. 두 계층은 서로를 대체하지 못한다. Security Group을 아무리 좁게 잡아도 IAM 자격 증명이 유출되면 공격자가 콘솔에서 그 Security Group을 열어버릴 수 있고, 반대로 IAM을 잘 통제해도 22번 포트를 전체 개방하면 서버 자체가 무차별 로그인 시도의 대상이 된다.

### 인바운드 규칙

| 유형 | 포트 | 소스 | 근거 |
| --- | --- | --- | --- |
| HTTP | 80 | `0.0.0.0/0` | 불특정 다수에게 제공하는 웹 서비스이므로 전체 개방이 목적에 부합 |
| SSH | 22 | 학습자 개인 IP `/32` | 관리자 1인만 사용. 전체 개방 시 무차별 로그인 시도 대상이 됨 |

`0.0.0.0/0`에 대한 전체 포트(0-65535) 허용 규칙은 생성하지 않았다.

인스턴스 생성 시점에는 SSH 소스가 `0.0.0.0/0`으로 설정되어 있었으며, 최종 점검 과정에서 이를 발견해 개인 IP `/32`로 수정했다. 상세 경위는 [트러블슈팅 보고서 사례 3](docs/troubleshooting.md)에 기록했다.

### IAM 최소권한

실습 전용 IAM 사용자 `cody-iam`에 `AmazonEC2FullAccess` 한 개만 연결했다. VPC, 서브넷, 라우팅 테이블, Internet Gateway, Security Group은 모두 EC2 서비스 네임스페이스(`ec2:*`)에 속하므로 이 정책 하나로 실습 범위가 커버된다. S3, RDS 등 실습과 무관한 서비스 권한은 부여하지 않았고, `AdministratorAccess`도 부여하지 않았다.

**최소권한을 적용하는 이유**는 사고 발생 시 피해 범위를 제한하기 위함이다. 액세스 키가 저장소에 실수로 커밋되는 사고는 드물지 않은데, 이때 키에 관리자 권한이 붙어 있으면 계정 전체가 장악되고 대규모 리소스가 무단 생성되어 과금으로 이어진다. 권한이 EC2로 한정되어 있으면 피해가 그 범위에서 멈춘다.

**한계와 개선 방향**: `AmazonEC2FullAccess`도 엄밀한 의미의 최소권한은 아니다. EC2 네임스페이스 안에서는 삭제를 포함한 모든 작업이 가능하기 때문이다. 더 좁히려면 `ec2:RunInstances`, `ec2:CreateVpc`, `ec2:CreateSecurityGroup`, `ec2:Describe*`, `ec2:CreateTags` 등 실습에 필요한 액션만 열거한 커스텀 정책을 사용하고, `Condition`으로 리전을 `ap-northeast-2`로 제한할 수 있다. 이번 실습에서는 작업 도중 권한 거부로 진행이 막히는 것을 피하기 위해 관리형 정책을 사용했다.

---

## 5. 트래픽 흐름

외부 요청이 EC2의 Nginx까지 도달하려면 아래 조건이 모두 충족되어야 한다. 하나라도 빠지면 요청은 도달하지 못한다.

1. **Internet Gateway가 VPC에 연결(Attached)** — 연결되지 않으면 라우팅 테이블의 IGW 경로 상태가 `Blackhole`이 된다.
2. **라우팅 테이블에 `0.0.0.0/0 → IGW` 경로 존재** — 문은 있어도 그리로 가라는 경로가 없으면 패킷이 나가지 못한다.
3. **해당 라우팅 테이블이 서브넷에 연결** — 경로는 서브넷 단위로 적용된다.
4. **인스턴스에 퍼블릭 IP 할당** — 외부에서 지정할 목적지 주소가 있어야 한다.
5. **Security Group 인바운드에 80번 허용** — 여기서 막히면 패킷이 인스턴스에 도달해도 폐기된다.
6. **인스턴스 내부에서 웹 서버가 80번을 리스닝** — `curl http://localhost`로 확인하는 항목이다.

1~4는 네트워크 경로, 5는 접근 제어, 6은 애플리케이션 계층이다. 장애 발생 시 이 순서로 좁혀나가면 원인을 빠르게 특정할 수 있다.

---

## 6. 문서

| 파일 | 내용 |
| --- | --- |
| [`docs/architecture.png`](docs/architecture.png) | 아키텍처 다이어그램 |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | 트러블슈팅 보고서 (3건) |
| [`docs/cleanup-checklist.md`](docs/cleanup-checklist.md) | 리소스 정리 체크리스트 |
| `docs/images/` | 검증 스크린샷 |
