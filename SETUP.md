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
- **応募フォームで住所・URLも受け取れます**
  → 応募者が住所・URLを入力すると `members` テーブルの `address`/`url` に自動で保存されます。
  ただし地図にピンを出すには `lat`/`lng`（緯度・経度）が別途必要なので、承認時にあわせて入力してください。
- **仲間を地図に表示したいとき**
  → `members` テーブルの `address`（所在地）・`lat`（緯度）・`lng`（経度）を入力してください。
  Googleマップで場所を検索 → 右クリック →「緯度、経度」をクリックするとコピーできます。
  `lat`/`lng` が未入力の会員は、地図には表示されず（一覧・人数カウントには表示されます）。
- **地図のピンにサイトへのリンクを出したいとき**
  → `members` テーブルの `url` に、お店・団体のサイトやSNSのURL（`https://` から始まるもの）を入力してください。
  地図上のピンをクリックすると、住所と一緒に「サイトを見る」リンクが表示されます。

  ※ 既にSupabaseプロジェクトを作成済みで `members` テーブルに `address`/`lat`/`lng`/`url` 列がない場合は、
  SQL Editorで次を実行してください。
  ```sql
  alter table members add column if not exists address text;
  alter table members add column if not exists lat double precision;
  alter table members add column if not exists lng double precision;
  alter table members add column if not exists url text;
  ```

## 5. 管理ページ（承認・却下）
サイトとは別に `admin.html` があり、ログインした管理者だけが応募の承認・却下・非公開への差し戻しができます。

### 初めて管理者を作るとき
1. Supabase管理画面 → 左メニュー「Authentication」→「Users」→「Add user」
   管理者にしたい人のメールアドレスとパスワードを設定して作成（「Auto Confirm User」はONにしてください）
2. 作成されたユーザーの行にある **User UID**（長い英数字）をコピー
3. 「SQL Editor」で次を実行（`<UUID>` をコピーしたものに置き換える）
   ```sql
   insert into admins (user_id) values ('<UUID>');
   ```
4. `admin.html` をブラウザで開き（例：`https://（アカウント名）.github.io/shinEDO/admin.html`）、
   設定したメールアドレスとパスワードでログイン

管理者を増やしたいときは、1〜3を繰り返してください（同じユーザーに対して2回INSERTしないよう注意）。

### 管理ページでできること
- 承認待ちの応募一覧の確認（連絡先・住所・URL・一言メッセージも表示）
- 「承認」ボタンで公開（`status` を `approved` に変更）
- 「非公開に戻す」ボタンで一覧から非表示に戻す
- 「削除」ボタンでデータそのものを削除

`admin.html` はGoogle検索などには載らないようにしてありますが、URLを知っていれば誰でもページ自体は開けます（ログインしない限り中身は操作できません）。より厳重にしたい場合は、URLを人に教えないようにしてください。

## 6. 会員本人によるログイン編集
`mypage.html`（サイトのナビの「マイページ」）から、会員本人が自分の登録内容（名前・区分・連絡先・住所・URL・一言）を編集できます。管理者の承認・削除・匠/一般の設定はできません。

- **応募と同時にアカウントが作られます**。応募フォーム（この指とーまれ）にメールアドレス・パスワードを入力して送信すると、Supabase Authのアカウント作成と会員データの登録が1回の操作で完了します。以降はそのメール・パスワードで`mypage.html`にログインするだけです
- この仕組みを追加する前に応募された既存の会員は、アカウントがまだ無い状態です。`mypage.html`の「こちらで新規登録」から、応募時と同じメールアドレスでアカウントを作れば、自動的に自分の応募データへ紐付けられます（`members.email` 列で照合。`contact`欄からベストエフォートで抽出済みですが、うまく抽出できていない場合は管理者が`members`テーブルの`email`列を手動で設定してください）

## 補足
- Supabaseの設定をしなくても、HTML単体で見た目の確認はできます（お話会・会員欄は「Supabase未接続」と表示されます）
- 無料枠の範囲であれば費用はかかりません
