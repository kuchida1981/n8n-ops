## Context

`n8n-deploy.yml`は`n8n/**`配下の変更が`main`にマージされた際に起動し、`production` Environmentの承認待ちで一時停止する。承認者は「Review pending deployments」画面からリンクされたワークフロー実行ページを見て承認するが、現状はワークフロー名(`n8n Deploy`)としか表示されず、何のバージョン変更を承認しようとしているのかを画面上で判別できない。

`n8n/docker-compose.yml`には`n8n`と`traefik`の2つのイメージが定義されており、Dependabotはどちらの更新でもこのファイルにPRを作成する(現在オープン中のPR #2はtraefik v3.7.5→v3.7.7の更新)。ワークフローのトリガーは`n8n/**`全体であり、n8n・traefikを区別しない。

## Goals / Non-Goals

**Goals:**
- 承認者がワークフロー実行一覧・Review pending deployments画面のリンク先タイトルから、対象のコミットメッセージを読み取れるようにする
- 承認前(ワークフロー実行の詳細ページ)で、`n8n/docker-compose.yml`内の`image:`行の変更差分を確認できるようにする
- n8n・traefikいずれのイメージ更新であっても、また将来`n8n/docker-compose.yml`に別サービスが追加された場合でも、分岐なく同じ仕組みで機能する

**Non-Goals:**
- GitHub純正の「Review pending deployments」画面自体のカスタマイズ(GitHub側の制約により不可能)
- `docker-compose.yml`以外のファイル変更(env、設定ファイルなど)の差分表示
- Dependabot以外の情報源(リリースノート等)の自動取得

## Decisions

### `run-name`でコミットメッセージをそのまま実行タイトルにする
`run-name: ${{ github.event.head_commit.message }}`を追加する。Dependabotのコミットメッセージ(例: `Bump traefik from v3.7.5 to v3.7.7 in /n8n`)がそのままタイトルになるため、追加の文字列加工は不要。squash-merge時のコミットタイトル設定(`COMMIT_OR_PR_TITLE`)により、手動マージでも意図した文言になることをPR #2で確認する(検証タスク参照)。

代替案として、`image:`行だけを抽出してタイトルに整形することも検討したが、コミットメッセージをそのまま使う方が実装コストが低く、Dependabot以外の手動コミット(将来的なtraefikの設定変更など)でも意味のあるタイトルになりやすいため採用しない。

### ジョブサマリーへの`image:`行diff出力は特定イメージ名に依存しない
```bash
git diff HEAD^ HEAD -- n8n/docker-compose.yml | grep '^[+-].*image:' >> "$GITHUB_STEP_SUMMARY"
```
`image:`という行パターンにのみ依存し、n8n/traefikを名指しで区別するロジックは持たない。これにより、対象がn8nでもtraefikでも、あるいは将来別サービスが追加されても実装変更なしで機能する。

`grep`がマッチなし(該当ファイルにimage行の変更がない、例: 環境変数のみの変更)の場合は終了コード1を返すため、`|| true`等でジョブが失敗しないようにする。

### diff出力用に承認ゲートなしの`summary`ジョブを新設する
GitHub Actionsの環境保護ルール(required reviewers)は、そのジョブの**実行開始そのもの**をブロックする。既存の`deploy`ジョブは`environment: production`を持つため、承認が下りるまでchekoutを含むどのステップも実行されない。つまり、diff出力ステップを`deploy`ジョブの中に追加しても、承認前にSummaryタブへ表示することはできず、issue #20の目的(承認前に差分を確認できる)を満たせない。

これを解決するため、ワークフローを2ジョブ構成に変更する:
- `summary`ジョブ(environment指定なし): `actions/checkout`(`fetch-depth: 2`で`HEAD^`を取得可能にする)を行い、image diffを`$GITHUB_STEP_SUMMARY`に出力する。ゲートがないため即座に実行される
- `deploy`ジョブ(`environment: production`、`needs: summary`): 既存のVM反映処理はそのまま。`summary`ジョブの完了を待って承認待ち状態になる

承認者がRunページを開いた時点で`summary`ジョブは完了済みであり、そのSummary出力は承認前から閲覧できる。`run-name`はワークフロー実行全体に対する設定のため、ジョブ分割の影響を受けない。

代替案として、`deploy`ジョブの中でcheckoutとdiff出力を承認前に済ませる方法も検討したが、GitHub Actionsの仕様上ジョブ単位でしか承認ゲートを制御できないため不可能であり、ジョブ分割以外の選択肢はない。

### 検証はテスト用の変更を作らず、既存のDependabot PR #2を使う
新規に検証用コミットを作るのではなく、現在オープン中のPR #2(traefik更新)を実装後にマージし、実際の「Review pending deployments」画面で確認する。理由:
- 実運用のデプロイフローをそのまま検証でき、モックや作り物のシナリオより信頼性が高い
- n8nではなくtraefikの更新であるため、「image種別を区別しない」という設計意図の確認にもなる

## Risks / Trade-offs

- [`.github/workflows/n8n-deploy.yml`自体の変更は`paths: n8n/**`にマッチせず、mainにマージしてもデプロイは起動しない] → 意図通り(ワークフロー定義の変更だけでVMへの反映は不要なため)。ただし検証時の順序に影響するため、tasks.mdに明記する: 本変更を先にmainへマージしてから、PR #2をマージすること
- [`git diff HEAD^`はマージコミットが単一の親を持つ前提(squash/fast-forward)] → 現状の運用(squash-mergeがデフォルト設定)と一致するため許容。マージコミット(2親)の場合は`HEAD^1`との比較になり得るが、現行運用では発生しない
- [`grep`がマッチしない場合の終了コード] → ステップ内で`|| true`を使い、ジョブの成否に影響させない

## Migration Plan

1. `.github/workflows/n8n-deploy.yml`に`run-name`を追加し、`summary`ジョブ(checkout + diff出力)を新設、既存の`deploy`ジョブに`needs: summary`を追加してmainにマージする(このマージ自体はdeployを起動しない)
2. PR #2(traefik v3.7.5→v3.7.7)をマージする
3. 起動したワークフロー実行のタイトルとSummaryタブを確認し、意図通りの表示になっているか確認する
4. 問題なければそのままPR #2の承認・デプロイを進める(通常のtraefikバージョン更新として扱う)

ロールバックは`run-name`行とサマリー出力ステップを削除するだけで、デプロイ本体のロジックに影響しない。

## Open Questions

(なし)
