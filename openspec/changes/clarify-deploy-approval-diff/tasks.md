## 1. ワークフロー実装

- [x] 1.1 `.github/workflows/n8n-deploy.yml`に`run-name: ${{ github.event.head_commit.message }}`を追加する
- [x] 1.2 承認ゲートなしの`summary`ジョブを新設し、`actions/checkout`(`fetch-depth: 2`)を行ったうえで、`n8n/docker-compose.yml`の`HEAD^`との差分から`image:`行の変更のみを抽出して`$GITHUB_STEP_SUMMARY`へ出力する(`grep`が非マッチの場合もジョブを失敗させないこと)
- [x] 1.3 既存の`deploy`ジョブに`needs: summary`を追加し、`summary`ジョブの完了後にのみ承認待ちへ進む構成にする

## 2. mainへの反映

- [ ] 2.1 本変更(`.github/workflows/n8n-deploy.yml`のみの変更)をmainへマージする(`paths: n8n/**`に該当しないため、このマージ自体はn8n-deployを起動しない)

## 3. 実運用での検証(PR #2を使用)

- [x] 3.1 タスク2.1がmainに反映されていることを確認したうえで、PR #2(`Bump traefik from v3.7.5 to v3.7.7 in /n8n`)をマージする
- [x] 3.2 起動した`n8n Deploy`ワークフロー実行のタイトルが、PR #2のコミットメッセージ(`Bump traefik from v3.7.5 to v3.7.7 in /n8n`相当)になっていることを確認する
- [x] 3.3 同ワークフロー実行のSummaryタブに、`traefik:v3.7.5` → `traefik:v3.7.7`の`image:`行の差分が表示されていることを確認する
- [x] 3.4 「Review pending deployments」画面から、上記タイトル・Summaryの内容が承認前に判別できることを確認したうえで承認し、通常通りデプロイが完了することを確認する

## 4. 検証で判明した事項

実際のRun(https://github.com/kuchida1981/n8n-ops/actions/runs/29091639852)で確認した際に判明した2点:

- タイトルが長い: squash-mergeのコミットメッセージ設定(`COMMIT_MESSAGES`)により、Dependabotのトレーラー(changelog・`Signed-off-by`等)を含む全文がそのまま`run-name`に表示される。GitHub Actionsの式言語には文字列を1行目だけ切り出す手段がなく、ワークフロー単体では解決不可。リポジトリ全体のsquash-merge設定変更が必要だが、影響範囲が本変更のスコープを超えるため、現状のまま許容することとした(重要な情報=バージョン変更自体は伝わっているため)
- `summary`ジョブの表示が"summary summary"のように重複して見える: `name:`未設定でジョブIDがそのまま表示名に使われていたため。PR #25で`name: Image version summary`を設定して解消(別PRとして対応、次回のn8n/traefikアップデート時に表示を確認する)
