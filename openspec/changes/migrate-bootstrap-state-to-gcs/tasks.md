## 1. コード変更(実装者が行う)

- [ ] 1.1 `terraform/bootstrap/versions.tf`に`backend "gcs" { prefix = "bootstrap" }`を追加する(bucket名はハードコードせず、`terraform/main/versions.tf`と同じ部分設定パターンにする)
- [ ] 1.2 `README.md`のセットアップ手順セクションを更新し、(a)既存環境向け: `-backend-config`を指定した`terraform init`手順、(b)真にゼロからの新規プロジェクト向け: 一時的なローカルbackendでの`apply`→`-migrate-state`手順、の両方を追記する
- [ ] 1.3 `README.ja.md`に同内容を日本語で反映する
- [ ] 1.4 追記した手順内のコマンド例(bucket名・prefix・出力名など)が実際のコード(`variables.tf`/`outputs.tf`/`versions.tf`)と整合していることをレビューする

## 2. 既存環境(kuchida-devel)の移行 — [ユーザーが手動で実行する作業]

**注意**: この節の作業は認証情報を伴う破壊的になりうる操作のため、実装者(Claude)は実行せず、ユーザー自身が手元のマシンで実行する。

- [ ] 2.1 [ユーザー作業] `terraform/bootstrap`ディレクトリの現在のローカルstate(`terraform.tfstate`・`terraform.tfstate.backup`)を、リポジトリ外の安全な場所にバックアップする
- [ ] 2.2 [ユーザー作業] `terraform output state_bucket`で移行先バケット名を確認する
- [ ] 2.3 [ユーザー作業] タスク1.1のコード変更を取り込んだ上で、`terraform init -backend-config="bucket=<state_bucket出力値>" -migrate-state`を実行し、ローカルstateをGCS(`bootstrap/`prefix)へ移行する
- [ ] 2.4 [ユーザー作業] 移行直後に同一マシンで`terraform plan`を実行し、差分が0件(No changes)であることを確認する
- [ ] 2.5 [ユーザー作業] 別マシン(または別の作業ディレクトリにクローンした同一リポジトリ)から、タスク2.3と同じ`-backend-config`で`terraform init`→`terraform plan`を実行し、ローカルstate不在に起因する誤差分が出ないことを確認する
- [ ] 2.6 [ユーザー作業] 移行完了後、バックアップ済みのローカルstateファイルは誤って再利用されないよう、作業ディレクトリから削除するか隔離する(gitignore対象のため誤コミットのリスクはないが、混乱防止のため)

## 3. ドキュメント確認

- [ ] 3.1 README.md/README.ja.mdの新しいセットアップ手順を読み直し、実際にタスク2で行った手順と一言一句ズレがないことを確認する(手順とコードの乖離を防ぐため)
