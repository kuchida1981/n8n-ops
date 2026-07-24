## 1. コード変更(実装者が行う)

- [x] 1.1 `terraform/bootstrap/main.tf`の`terraform_ci_roles`(または専用リソース)に、`google_project_service.required`・WIF Pool/Provider・project IAMポリシーを読み取るための最小限のViewer系ロールを追加する
- [x] 1.2 `.github/workflows/terraform-plan.yml`に、`terraform/bootstrap`専用のjob(またはstep群)を追加する。既存の`terraform/main`用jobは変更しない。dependabotのactor判定(`pull_request`/`pull_request_target`)は既存jobと同じパターンを踏襲する
- [x] 1.3 追加したbootstrap用jobのrelevance-check(diff対象パス)が`terraform/bootstrap`と自身のワークフローファイルのみを見ており、`terraform/main`用jobのrelevance-checkと独立していることを確認する
- [x] 1.4 bootstrap用jobの`terraform init`が、`terraform/main`用jobと同じ`TF_STATE_BUCKET`シークレットを`-backend-config`で使うようにする(bootstrap用の変数は`project_id`・`github_repo`のみで、tailscale系変数は不要であることを確認する)
- [x] 1.5 README.md/README.ja.mdに、`terraform/bootstrap`はplanのみCI化されapplyは引き続き手動である旨を追記する
- [x] 1.6 `terraform fmt -check`・`terraform validate`(backend未接続)でbootstrapの構文を確認する

## 2. 権限反映 — [ユーザーが手動で実行する作業]

**注意**: `terraform/bootstrap`はCIからapplyできない設計を維持しているため、コード変更後の実際の権限付与は、認証情報を持つユーザー自身が手動で実行する。

- [x] 2.1 [ユーザー作業] タスク1.1のコード変更を取り込んだ上で、README記載の既存環境向け手順(`terraform init -backend-config="bucket=<state_bucket>"` → `terraform apply -var="project_id=..." -var="github_repo=..."`)で`terraform/bootstrap`を手動applyし、CI用SA(`terraform_ci`)に新しいViewer系ロールを付与する
- [x] 2.2 [ユーザー作業] applyの差分が、追加したロールの付与のみであり、他のリソースに意図しない変更が無いことを確認する(実際に`Plan: 3 to add, 0 to change, 0 to destroy.`で、追加された3ロール以外への影響なしを確認)
- [ ] 2.3 [ユーザー作業] PR #43でのplan実地確認(タスク3.1)で`storage.buckets.get`権限不足が判明したため追加した`roles/storage.legacyBucketReader`(バケットスコープ)を、同じ手動apply手順で反映する

## 3. 動作確認 — [ユーザーが手動で実行する作業]

- [ ] 3.1 [ユーザー作業] PR #43(本change自体のPR、`terraform/bootstrap/main.tf`を変更しているため実地確認を兼ねる)で、タスク2.3の権限反映後に`plan-bootstrap` jobを再実行し、CI上で`terraform plan`が正常終了(`No changes`または想定通りの差分)し、PRにplan結果がコメントされることを確認する
- [ ] 3.2 [ユーザー作業] 同じPR上で、`terraform-apply.yml`が起動していない(=applyが自動実行されていない)ことを確認する
