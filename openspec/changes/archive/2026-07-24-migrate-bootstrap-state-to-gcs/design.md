## Context

`terraform/bootstrap`は、`terraform/main`が使うリモートbackend用のGCSバケット・WIF Pool/Provider・CI用サービスアカウントを作成する。これらはterraform自身が依存する前提リソースであるため、`terraform/main`のようにリモートbackendへ最初から依存することができず(バケットがまだ存在しない)、意図的にローカルstate管理になっている。

この「鶏と卵」構造自体は変えられないが、実際に問題になっているのは別の話で、**bootstrapが一度適用されバケットが存在した後**も、そのbootstrap自身のstateがローカルのまま放置されている点である。ローカルstateはgit管理外でマシンに紐づくため、別マシンから触ると「stateが見えない」状態になり、vaultwarden-opsで実際に誤った差分("17 to add")が出る事故が起きた。n8n-opsは同一構造を持つため、同じ事故を起こし得る。

## Goals / Non-Goals

**Goals:**
- 既存環境(kuchida-devel)のbootstrap stateを、どのマシンからでも同じ内容を参照できるGCSリモートバックエンドへ移行する。
- 新規バケットを作らず、bootstrap自身が作成する既存のtfstateバケットを、prefixを分けて再利用する。
- `terraform/main`と一貫したbackend設定パターン(部分設定 + `-backend-config`で注入)を踏襲する。

**Non-Goals:**
- bootstrapの「初回は手動・ローカルで1回だけ実行する」という根本設計自体を変えることはしない(GCSバックエンドはバケットを自動作成しないため、真にゼロからの初回実行における鶏と卵問題は原理的に解消できない)。
- CI(GitHub Actions)からbootstrapを実行できるようにすることは範囲外。bootstrapは引き続き手動実行のみ。

## Decisions

### 決定1: backendブロックは常設し、bucket名は`-backend-config`で注入する部分設定にする(案A)

`terraform/bootstrap/versions.tf`に以下を追加する:

```hcl
backend "gcs" {
  prefix = "bootstrap"
}
```

`terraform/main/versions.tf`と同じパターン(bucket名をハードコードせず`-backend-config="bucket=..."`で注入)を踏襲する。

**検討した代替案(案B): backendブロックを常設せず、運用ルール(README記載の手順)だけで「既存環境では必ずmigrate-stateすること」を徹底する**

- 却下理由: 技術的な強制力がない。vaultwarden-opsの事故は、まさに「手順を徹底していたはずが、別マシンだったので誰も気づかなかった」というケースで発生している。運用ルール任せでは同種の事故の再発を防げない。既存環境で実際に事故った実績がある以上、既存環境を技術的に保護することを優先する。

### 決定2: 新規バケットを作らず、既存tfstateバケットのprefixを分けて再利用する

`google_storage_bucket.tfstate`(`${var.project_id}-n8n-tfstate`)は`terraform/main`用に既に存在する。bootstrap自身のstate用に別バケットを新設せず、同一バケット内で`prefix = "bootstrap"`として分離する。

- 理由: バケットを増やすと、bootstrapがそのバケット自体を管理しなければならなくなり(=もう一段階の鶏と卵)、運用が複雑化する。GCSバックエンドはprefixによるオブジェクトパス分離で十分にstateを分離できるため、単一バケット+prefix分離で要件を満たせる。

### 決定3: 「真にゼロから新規GCPプロジェクトを立ち上げる」ケースは、初回のみ一時的にlocal backendで運用する手順をREADMEに残す

backendブロックを常設すると、バケットがまだ存在しない真の初回実行では`terraform init`が失敗する(GCSバックエンドはバケットを自動作成しない)。このケースは以下の手順で乗り切る:

1. `versions.tf`の`backend "gcs"`ブロックを一時的にコメントアウト(またはローカルbackendのまま)で`terraform init && terraform apply`し、バケットとその他前提リソースを作成する。
2. `backend "gcs"`ブロックを有効化し、`terraform init -backend-config="bucket=<出力されたstate_bucket>" -migrate-state`でstateをGCSへ移す。
3. 以降は他の運用者も同じ`-backend-config`でリモートbackendに接続できる。

- 発生頻度: 現時点でn8n-ops/vaultwarden-hosting/u-rei.com-dnsは`kuchida-devel`という単一GCPプロジェクトを共有しており([[kuchida-devel-shared-gcp]])、新規プロジェクトを一から立ち上げる機会は稀。稀にしか発生しない手間のために、既に事故実績のある既存環境の保護を犠牲にはしない。

## Risks / Trade-offs

- [Risk] bootstrapが管理するバケット自体に、bootstrap自身のstateも保存する自己参照的な構成になる → [Mitigation] バケットには`force_destroy = false`・`public_access_prevention = "enforced"`・`versioning`が既に設定されており、誤destroy・誤公開・誤上書きに対する保護は元から備わっている。多くのTerraform運用で採用されている一般的なパターンでもある。
- [Risk] `-migrate-state`実行時に誤ったbucket名を指定すると、意図しない場所にstateが分散する → [Mitigation] bucket名はbootstrap自身の`terraform output state_bucket`から取得して指定する手順をREADMEに明記し、タイポの余地を減らす。
- [Risk] 移行作業中(ローカルstate→GCS)に他の誰かが同時にbootstrapのstateを操作すると競合する可能性がある → [Mitigation] bootstrapは元々手動・単独運用のため実質的なリスクは低いが、移行はメンテナンスウィンドウとして一人で完結させる運用注意をREADMEに記載する。
- [Trade-off] 真にゼロからの新規プロジェクト立ち上げ時、手順が「apply→backend有効化→migrate-state」の3ステップに増え、以前より複雑になる → 発生頻度が低いことを踏まえ許容する(決定3参照)。

## Migration Plan

1. `terraform/bootstrap/versions.tf`に`backend "gcs" { prefix = "bootstrap" }`を追加する(コード変更)。
2. 既存環境(kuchida-devel)のローカル`terraform.tfstate`をバックアップする。
3. `terraform init -backend-config="bucket=<state_bucket出力値>" -migrate-state`を実行し、ローカルstateをGCSへ移行する(ユーザーが手動実行)。
4. 別マシンから`terraform init`(同じ`-backend-config`)→`terraform plan`を実行し、差分が出ない(=誤検知がない)ことを確認する(ユーザーが実施)。
5. README.md/README.ja.mdに、既存環境向け手順と新規環境向け手順の両方を追記する。

ロールバック: 移行に失敗した場合、バックアップしたローカル`terraform.tfstate`を復元し、`versions.tf`のbackendブロックを削除して`terraform init -migrate-state`で元に戻す。GCS側のバケットには`versioning`が有効なため、誤ったstate書き込みも旧バージョンから復旧可能。

## Open Questions

- なし(既存の`state_bucket`出力・既存バケットをそのまま再利用する方針で解決済み)。
