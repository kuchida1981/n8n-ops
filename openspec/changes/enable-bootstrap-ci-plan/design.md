## Context

`terraform/bootstrap`は、issue #30の対応(`migrate-bootstrap-state-to-gcs`)により、既に自身のstateをGCSリモートバックエンド(`kuchida-devel-n8n-tfstate`バケット、`bootstrap/`prefix)で管理している。しかしCIワークフロー(`terraform-plan.yml`/`terraform-apply.yml`)は依然`terraform/main`のみを対象にしており、`.github/dependabot.yml`が週次で作成する`terraform/bootstrap`向けのdependabot PRは、CI上では何も検証されないまま放置される。マージしても`terraform-apply.yml`のpathフィルタに含まれないため反映されない。

## Goals / Non-Goals

**Goals:**
- `terraform/bootstrap`向けのdependabot PRに対して、CI上で`terraform plan`を実行しPRにコメントする。
- 既存の`terraform/main`用CIロジックに影響を与えない形で実現する。
- planに必要な最小限の読み取り専用権限をCI用SAに付与する。

**Non-Goals:**
- CIからの`terraform/bootstrap`自動apply(issue #41のスコープ外として明示済み)。
- `terraform_ci`への書き込み・管理系(Admin)権限の追加。今回追加するのは読み取り専用(Viewer系)ロールのみ。

## Decisions

### 決定1: 既存jobのmatrix化ではなく、bootstrap専用のjob/stepを新設する(案B)

**検討した代替案(案A): `terraform-plan.yml`の既存jobを`matrix: [terraform/main, terraform/bootstrap]`化する**

- 却下理由: `terraform/main`はTailscale関連の変数(`TF_VAR_tailscale_tailnet`等)を必要とするが、`terraform/bootstrap`はそれらを一切使わず`project_id`/`github_repo`のみで完結する。matrix化すると、変数セットの違いを`if`分岐やmatrix変数のマッピングで表現する必要があり、可読性が下がる。また、bootstrap側の追加(将来的な拡張)がmain側のロジックに影響を与えるリスクも生まれる。

**採用: 案B、bootstrap専用のjob(またはstep群)を追加する**

- 既存の`plan` jobはそのまま変更せず、新しい`plan-bootstrap`のようなjobを追加する。
- actor判定(`pull_request`/`pull_request_target`とdependabot判定の組み合わせ)は既存jobと同じパターンを踏襲する。
- diff検出ステップも同様に`terraform/bootstrap .github/workflows/terraform-plan.yml`を対象にした専用のrelevance-checkを持たせる(mainのrelevance-checkとは独立させる。片方の変更が無関係なPRでもrequired checkが無限にpendingしないようにするため、mainのjobと同様、diffが無関係でも空振りで正常終了する構成を維持する)。

### 決定2: CI用SAに読み取り専用(Viewer系)ロールを追加し、付与は人間の手動applyに委ねる

`terraform plan`はstateとの差分を出すために、現在の実リソースをrefreshする。これには書き込み権限は不要だが、対象リソースへの読み取り権限は必要。bootstrapが管理するリソースのうち、現在のCI SAのロールセットでカバーされていないものは:

| リソース | 必要な読み取り権限(相当) |
|---|---|
| `google_project_service.required` | serviceusage系のViewer |
| `google_iam_workload_identity_pool` / `_provider` | `roles/iam.workloadIdentityPoolViewer` |
| `google_project_iam_member.terraform_ci_roles` | project IAMポリシーの読み取り(`resourcemanager.projects.getIamPolicy`相当) |

これらを`terraform/bootstrap/main.tf`の`terraform_ci_roles`(または専用のfor_eachリソース)に追加する。ただし、この変更はbootstrap自身のIaCコードの変更であり、CIはbootstrapをapplyできない設計(決定3・元issue #30/#41の前提)を維持するため、**コード変更後に人間が手動で`terraform apply`する**必要がある。これはplan自動化を実現するための一度きりのセットアップ作業として扱う。

- 検討した代替案: 「読み取り権限が無いままplanを実行し、一部リソースだけrefreshエラーが出る状態を許容する」→却下。CIのplan結果が信頼できなくなり、"また誤った差分/エラーで無視される" という別の形の放置リスクを生むため、最初から正しく動く状態を用意する。

### 決定3(既存判断の再確認): apply自動化はしない

issue #41で既に整理した通り、bootstrapは`terraform_ci`自身・WIF Pool/Provider・そのSAへのIAMロール付与を管理するため、CIがbootstrapをapplyできると自己権限昇格の経路になり得る。この判断は変更しない。今回追加する読み取り専用ロールも、あくまで人間が手動applyする対象であり、CIには一切追加権限を自動付与させない。

## Risks / Trade-offs

- [Risk] 読み取り専用ロールの粒度を誤ると、意図せず広い権限を付与してしまう可能性 → [Mitigation] project単位のプリセットロールではなく、可能な限り対象リソースに絞ったViewer系ロール(`roles/iam.workloadIdentityPoolViewer`等)を選定し、`compute.admin`のような広範なAdminロールは追加しない。
- [Risk] bootstrap専用jobを追加することでワークフローの複雑性が増し、mainとbootstrapで挙動差異(例: relevance-checkのロジック重複)が生じるリスク → [Mitigation] 既存jobのstep構成をテンプレートとしてそのまま踏襲し、変数とworking-directoryのみ差し替える形にする。
- [Trade-off] plan有効化のために人間の手動apply作業が一度必要になる(issue #30の移行作業と同様のパターン) → 発生は一度きりであり、以後は自動化されたplanの恩恵を継続的に受けられるため許容する。

## Migration Plan

1. `terraform/bootstrap/main.tf`に読み取り専用ロールを追加(コード変更)。
2. `terraform-plan.yml`にbootstrap用job/stepを追加(コード変更)。
3. README更新(コード変更)。
4. 人間が`terraform/bootstrap`を手動applyし、追加ロールを実際にkuchida-devel環境のCI SAへ反映する(ユーザー作業)。
5. 既存または新規のbootstrap向けdependabot PRを開き(または既存のものを再実行し)、CI上でplanが正常に実行されPRにコメントされることを確認する(ユーザー作業)。

ロールバック: ワークフローYAMLの変更を戻せばCI plan自動化は無効化される。IAMロールの追加は読み取り専用であり、誤って付与してもセキュリティ上のリスクは低いが、不要になれば`terraform/bootstrap/main.tf`から該当ロールを削除して再度手動applyすれば元に戻せる。

## Open Questions

- 追加する具体的なロール名(`roles/iam.workloadIdentityPoolViewer`など)は、実装時に`terraform plan`を実際に試行しエラーメッセージを見ながら過不足なく決定する(タスクで明記)。
