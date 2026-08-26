# shinEDO project HP — セットアップ手順

## 1. Supabaseプロジェクトを作る
1. https://supabase.com で新規プロジェクトを作成
2. 左メニュー「SQL Editor」を開き、`supabase-schema.sql` の中身を丸ごと貼り付けて実行
   → `members`（会員）と `events`（お話会）の2つのテーブルができます
3. 左メニュー「Project Settings」→「API」から、以下の2つをコピー
   - Project URL
   - anon public key

## 2. index.html にキーを設定する
`index.html` の一番下、`<script>` の中にある以下の2行を書き換えます。

```js
const SUPABASE_URL = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

↓ コピーした値に置き換える

```js
const SUPABASE_URL = 'https://xxxxxxxx.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOi...（長い文字列）';
```

## 3. GitHub Pagesで公開する
1. GitHubで新しいリポジトリを作成（例：`shinedo-project`）
2. `index.html` をアップロード
3. リポジトリの Settings → Pages → Branch を `main` に設定して保存
4. しばらくすると `https://（あなたのアカウント名）.github.io/shinedo-project/` で公開されます

## 4. 会員・お話会の管理方法
プログラムを書かずに、Supabaseの管理画面だけで運用できます。

- **お話会を追加・変更したいとき**
  → Supabase「Table Editor」→ `events` テーブルで行を追加・編集
- **応募してきた会員を公開したいとき**
  → `members` テーブルで、該当する行の `status` を `pending` から `approved` に変更するだけで、サイトの会員一覧に表示されます
- **応募を断りたいとき**
  → その行を削除、または `status` をそのままにしておけば非公開のままです
- **仲間を地図に表示したいとき**
  → `members` テーブルの `address`（所在地）・`lat`（緯度）・`lng`（経度）を入力してください。
  Googleマップで場所を検索 → 右クリック →「緯度、経度」をクリックするとコピーできます。
  `lat`/`lng` が未入力の会員は、地図には表示されず（一覧・人数カウントには表示されます）。

  ※ 既にSupabaseプロジェクトを作成済みで `members` テーブルに `address`/`lat`/`lng` 列がない場合は、
  SQL Editorで次を実行してください。
  ```sql
  alter table members add column if not exists address text;
  alter table members add column if not exists lat double precision;
  alter table members add column if not exists lng double precision;
  ```

## 補足
- Supabaseの設定をしなくても、HTML単体で見た目の確認はできます（お話会・会員欄は「Supabase未接続」と表示されます）
- 無料枠の範囲であれば費用はかかりません
