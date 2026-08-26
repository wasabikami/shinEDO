-- ============================================================
-- shinEDO project — Supabase テーブル定義
-- Supabase管理画面の「SQL Editor」に、このファイルの内容を
-- そのまま貼り付けて実行してください。
-- ============================================================

-- 会員テーブル：応募フォームからの登録を受け取る
create table if not exists members (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  category text not null,       -- 個人 / 里・村 / コミュニティ / 団体・会社・企業
  name text not null,           -- お名前・団体名
  contact text,                 -- 連絡先
  address text,                 -- 所在地（地図・表示用）
  lat double precision,         -- 緯度（地図に表示する場合に設定）
  lng double precision,         -- 経度（地図に表示する場合に設定）
  message text,                 -- 一言メッセージ
  status text not null default 'pending'   -- pending（未承認） / approved（公開）
);

-- 既存のテーブルに address / lat / lng がまだ無い場合はこちらを実行
-- alter table members add column if not exists address text;
-- alter table members add column if not exists lat double precision;
-- alter table members add column if not exists lng double precision;

-- お話会テーブル：開催予定・実施履歴を管理する
create table if not exists events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  event_date date,              -- 開催日
  guest_name text,              -- ゲスト名（例：ビールの和ちゃん）
  theme text,                   -- テーマ・一言紹介
  note text,                    -- 補足メモ（サイトには非表示）
  status text not null default 'upcoming'   -- upcoming（予定） / done（終了）
);

-- ------------------------------------------------------------
-- RLS（Row Level Security）を有効化
-- ------------------------------------------------------------
alter table members enable row level security;
alter table events  enable row level security;

-- 会員：誰でも「応募」として新規登録できる（承認待ちのみ）
create policy "members: public insert"
  on members for insert
  to anon
  with check ( status = 'pending' );

-- 会員：承認済み（approved）のものだけ、誰でも閲覧できる
create policy "members: public read approved"
  on members for select
  to anon
  using ( status = 'approved' );

-- お話会：誰でも閲覧できる
create policy "events: public read"
  on events for select
  to anon
  using ( true );

-- ------------------------------------------------------------
-- 動作確認用のサンプルデータ（不要であれば削除してください）
-- ------------------------------------------------------------
insert into events (event_date, guest_name, theme, status) values
  ('2026-06-15', '克くん', '前回のお話会', 'done'),
  ('2026-08-24', 'ビールの和ちゃん', '今回のお話会', 'upcoming'),
  ('2026-09-21', '空手と歌手', '次回のお話会', 'upcoming'),
  ('2026-12-14', 'だるまさんの草履', '12月のお話会', 'upcoming');

insert into members (category, name, contact, address, lat, lng, status) values
  ('個人', '超人', null, null, null, null, 'approved'),
  ('団体・会社・企業', '達磨草履工房', null,
    '香川県仲多度郡まんのう町勝浦892番地', 34.0880579, 133.9916719, 'approved'),
  ('団体・会社・企業', 'MIROCビール', 'info@miroc-beer.com / 0877-43-7067',
    '香川県丸亀市北平山町2-5-15', 34.2888128, 133.7982421, 'approved'),
  ('団体・会社・企業', '愛菜ファーム Sin', null,
    '香川県丸亀市飯山町真時555', 34.2582117, 133.8473823, 'approved'),
  ('団体・会社・企業', '和咲美', null,
    '岡山県美作市真加部1057-4', 35.0796259, 134.1870792, 'approved');

-- ------------------------------------------------------------
-- 補足：lat/lng は町域レベルの目安座標です（番地までは正確ではありません）。
-- 新しい会員を地図に載せたい場合は、Googleマップで場所を右クリックし
-- 表示される緯度・経度をコピーして lat / lng 列に入力してください。
-- ------------------------------------------------------------
