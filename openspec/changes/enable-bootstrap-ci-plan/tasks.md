## 1. コード変更(実装者が行う)

- [ ] 1.1 `terraform/bootstrap/main.tf`の`terraform_ci_roles`(または専用リソース)に、`google_project_service.required`・WIF Pool/Provider・project IAMポリシーを読み取るための最小限のViewer系ロールを追加する
- [ ] 1.2 `.github/workflows/terraform-plan.yml`に、`terraform/bootstrap`専用のjob(またはstep群)を追加する。既存の`terraform/main`用jobは変更しない。dependabotのactor判定(`pull_request`/`pull_request_target`)は既存jobと同じパターンを踏襲する
- [ ] 1.3 追加したbootstrap用jobのrelevance-check(diff対象パス)が`terraform/bootstrap`と自身のワークフローファイルのみを見ており、`terraform/main`用jobのrelevance-checkと独立していることを確認する
- [ ] 1.4 bootstrap用jobの`terraform init`が、`terraform/main`用jobと同じ`TF_STATE_BUCKET`シークレットを`-backend-config`で使うようにする(bootstrap用の変数は`project_id`・`github_repo`のみで、tailscale系変数は不要であることを確認する)
- [ ] 1.5 README.md/README.ja.mdに、`terraform/bootstrap`はplanのみCI化されapplyは引き続き手動である旨を追記する
- [ ] 1.6 `terraform fmt -check`・`terraform validate`(backend未接続)でbootstrapの構文を確認する

## 2. 権限反映 — [ユーザーが手動で実行する作業]

**注意**: `terraform/bootstrap`はCIからapplyできない設計を維持しているため、コード変更後の実際の権限付与は、認証情報を持つユーザー自身が手動で実行する。

- [ ] 2.1 [ユーザー作業] タスク1.1のコード変更を取り込んだ上で、README記載の既存環境向け手順(`terraform init -backend-config="bucket=<state_bucket>"` → `terraform apply -var="project_id=..." -var="github_repo=..."`)で`terraform/bootstrap`を手動applyし、CI用SA(`terraform_ci`)に新しいViewer系ロールを付与する
- [ ] 2.2 [ユーザー作業] applyの差分が、追加したロールの付与のみであり、他のリソースに意図しない変更が無いことを確認する

## 3. 動作確認 — [ユーザーが手動で実行する作業]

- [ ] 3.1 [ユーザー作業] 既存のbootstrap向けdependabot PR(あれば)を再実行(re-run)するか、無ければ`terraform/bootstrap`の些細な変更(コメント追加等)で試験PRを作成し、CI上で`terraform plan`が正常終了し、PRにplan結果がコメントされることを確認する
- [ ] 3.2 [ユーザー作業] 同じPR上で、`terraform/bootstrap/**`を対象にした`terraform-apply.yml`が起動していない(=applyが自動実行されていない)ことを確認する
- [ ] 3.3 [ユーザー作業] 確認が取れたタスク3.1の試験PR(作成した場合)をクローズ/破棄する
