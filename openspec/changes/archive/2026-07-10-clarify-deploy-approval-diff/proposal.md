## Why

`n8n-deploy.yml`は`production` GitHub Environmentの承認ゲートを持つが、承認者が「Review pending deployments」画面で目にするのはマージコミットのメッセージ・汎用的な文言・ワークフロー名のみで、**何のバージョンから何のバージョンへの更新を承認しようとしているのか**が画面上で一目でわからない(Issue #20)。

## What Changes

- ワークフロー実行タイトルを`run-name: ${{ github.event.head_commit.message }}`でカスタマイズし、Review pending deployments画面からのリンク先タイトルにコミットメッセージ(例: Dependabotのバージョン更新メッセージ)がそのまま表示されるようにする
- ジョブサマリー(`$GITHUB_STEP_SUMMARY`)に、`n8n/docker-compose.yml`の`HEAD^`との差分から抽出した`image:`行の変更点を出力する。n8nイメージに限らず、`n8n/docker-compose.yml`内の変更された`image:`行すべて(traefikを含む)が対象
- このワークフローは`n8n/**`配下の変更全般(n8n・traefikいずれのイメージ更新や設定変更も含む)を対象としており、今回の変更もその対象範囲全体に適用される。imageの種類による分岐処理は設けない

## Capabilities

### New Capabilities
(なし)

### Modified Capabilities
- `deployment-pipeline`: 「承認ゲート付きn8nデプロイパイプライン」要件に、承認待ちのワークフロー実行が何のバージョン変更を含むかを承認前に判別可能にする、という要件を追加する

## Impact

- `.github/workflows/n8n-deploy.yml`: `run-name`の追加、バージョン差分をサマリー出力するステップの追加
- 影響範囲は`n8n/**`配下の変更全般(n8n・traefikいずれのDependabot更新や手動タグ変更も含む)
- 既存のデプロイ処理(承認後のVM反映処理)自体には変更なし
