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
  url text,                     -- お店・団体のサイトやSNSのURL（地図ポップアップに表示）
  message text,                 -- 一言メッセージ
  member_type text not null default 'general',  -- artisan（匠）/ general（一般）
  email text,                   -- ログイン用メールアドレス（本人編集の紐付けに使用。contactとは別）
  owner_id uuid references auth.users(id) on delete set null,  -- ログインしたご本人のアカウント
  status text not null default 'pending'   -- pending（未承認） / approved（公開）
);

-- 既存のテーブルに address / lat / lng / url / member_type / email / owner_id がまだ無い場合はこちらを実行
-- alter table members add column if not exists address text;
-- alter table members add column if not exists lat double precision;
-- alter table members add column if not exists lng double precision;
-- alter table members add column if not exists url text;
-- alter table members add column if not exists member_type text not null default 'general';
-- alter table members add column if not exists email text;
-- alter table members add column if not exists owner_id uuid references auth.users(id) on delete set null;

-- お話会テーブル：開催予定・実施履歴を管理する
create table if not exists events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  event_date date,              -- 開催日
  guest_name text,              -- ゲスト名（例：ビールの和ちゃん）
  theme text,                   -- テーマ・一言紹介
  detail text,                  -- サイト上に表示する詳細文章（あれば「詳細を見る」で開閉表示）
  url text,                     -- 詳細ページのURL（あれば併せて外部リンクも表示）
  note text,                    -- 補足メモ（サイトには非表示）
  status text not null default 'upcoming'   -- upcoming（予定） / done（終了）
);

-- 既存のテーブルに url / detail がまだ無い場合はこちらを実行
-- alter table events add column if not exists url text;
-- alter table events add column if not exists detail text;

-- 管理者テーブル：ログインして承認作業ができる人（Supabase Authのユーザーと1対1）
create table if not exists admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- ------------------------------------------------------------
-- RLS（Row Level Security）を有効化
-- ------------------------------------------------------------
alter table members enable row level security;
alter table events  enable row level security;
alter table admins  enable row level security;

-- 会員：誰でも「応募」として新規登録できる（承認待ちのみ、ログイン中の人も含む）
create policy "members: public insert"
  on members for insert
  to public
  with check ( status = 'pending' );

-- 会員：承認済み（approved）のものだけ、誰でも閲覧できる（ログイン中の人も含む）
create policy "members: public read approved"
  on members for select
  to public
  using ( status = 'approved' );

-- 会員：管理者はpending含む全件を閲覧できる
create policy "members: admin read all"
  on members for select
  to authenticated
  using ( exists (select 1 from admins where user_id = auth.uid()) );

-- 会員：管理者は承認・編集ができる
create policy "members: admin update"
  on members for update
  to authenticated
  using ( exists (select 1 from admins where user_id = auth.uid()) )
  with check ( exists (select 1 from admins where user_id = auth.uid()) );

-- 会員：管理者は却下（削除）ができる
create policy "members: admin delete"
  on members for delete
  to authenticated
  using ( exists (select 1 from admins where user_id = auth.uid()) );

-- お話会：誰でも閲覧できる（ログイン中の人も含む）
create policy "events: public read"
  on events for select
  to public
  using ( true );

-- お話会：ログイン中の管理者も閲覧できる（public readはanon限定のため別途必要）
create policy "events: admin read"
  on events for select
  to authenticated
  using ( exists (select 1 from admins where user_id = auth.uid()) );

-- お話会：管理者は追加・編集・削除ができる
create policy "events: admin insert"
  on events for insert
  to authenticated
  with check ( exists (select 1 from admins where user_id = auth.uid()) );

create policy "events: admin update"
  on events for update
  to authenticated
  using ( exists (select 1 from admins where user_id = auth.uid()) )
  with check ( exists (select 1 from admins where user_id = auth.uid()) );

create policy "events: admin delete"
  on events for delete
  to authenticated
  using ( exists (select 1 from admins where user_id = auth.uid()) );

-- 管理者：自分が管理者かどうかを確認できる（自分の行だけ）
create policy "admins: self read"
  on admins for select
  to authenticated
  using ( user_id = auth.uid() );

-- ------------------------------------------------------------
-- 管理者の一覧・追加・削除（メールアドレス指定）
-- admins/auth.usersへは直接select/insert/deleteの権限を渡さず、
-- 「今の自分が管理者かどうか」をサーバー側でチェックする関数経由でのみ操作させる。
-- ------------------------------------------------------------
create or replace function public.list_admins()
returns table (user_id uuid, email text)
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from admins ad where ad.user_id = auth.uid()) then
    raise exception 'not authorized';
  end if;

  return query
  select a.user_id, u.email::text
  from admins a
  join auth.users u on u.id = a.user_id
  order by u.email;
end;
$$;

create or replace function public.grant_admin(target_email text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  target_id uuid;
begin
  if not exists (select 1 from admins where user_id = auth.uid()) then
    raise exception 'not authorized';
  end if;

  select id into target_id from auth.users where email = target_email;
  if target_id is null then
    raise exception 'そのメールアドレスのユーザーが見つかりません（先にSupabase AuthでUserを作成してください）';
  end if;

  insert into admins (user_id) values (target_id) on conflict do nothing;
end;
$$;

create or replace function public.revoke_admin(target_email text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  target_id uuid;
begin
  if not exists (select 1 from admins where user_id = auth.uid()) then
    raise exception 'not authorized';
  end if;

  select id into target_id from auth.users where email = target_email;
  if target_id is null then
    raise exception 'ユーザーが見つかりません';
  end if;

  delete from admins where user_id = target_id;
end;
$$;

grant execute on function public.list_admins() to authenticated;
grant execute on function public.grant_admin(text) to authenticated;
grant execute on function public.revoke_admin(text) to authenticated;

-- ------------------------------------------------------------
-- 会員本人によるログイン編集
-- membersテーブルへの直接のselect/update権限は渡さず、
-- 「自分のowner_idが一致する行だけ」を扱う関数経由でのみ操作させる。
-- ------------------------------------------------------------

-- ログイン直後に1回呼ぶ：自分のメールアドレスと一致する未紐付けの会員行があれば、
-- 自分のアカウント（owner_id）として紐付ける。
-- 戻り値はjsonb（membersの行型のままだと、Postgresの仕様上「本当にNULL」を
-- 返してもJSONへの変換時に「全項目がnullのオブジェクト」になってしまい、
-- JS側で「見つからなかった」ことを正しく判定できないため）
drop function if exists public.claim_member();
drop function if exists public.get_my_member();

create or replace function public.claim_member()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_email text := (select email from auth.users where id = auth.uid());
  v_id uuid;
  v_row members;
begin
  if v_email is null then
    raise exception 'not authenticated';
  end if;

  select id into v_id from members where email = v_email and owner_id is null limit 1;
  if v_id is not null then
    update members set owner_id = auth.uid() where id = v_id;
  end if;

  select * into v_row from members where owner_id = auth.uid();
  if not found then
    return null;
  end if;
  return to_jsonb(v_row);
end;
$$;

-- 自分に紐付いている会員情報を取得
create or replace function public.get_my_member()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_row members;
begin
  select * into v_row from members where owner_id = auth.uid();
  if not found then
    return null;
  end if;
  return to_jsonb(v_row);
end;
$$;

-- 自分の会員情報を編集（status・member_type・owner_idは変更不可）
create or replace function public.update_my_member(
  p_name text, p_category text, p_contact text, p_address text,
  p_lat double precision, p_lng double precision, p_url text, p_message text
)
returns members
language plpgsql security definer set search_path = public as $$
declare
  v_row members;
begin
  update members set
    name = p_name,
    category = p_category,
    contact = p_contact,
    address = p_address,
    lat = p_lat,
    lng = p_lng,
    url = p_url,
    message = p_message
  where owner_id = auth.uid()
  returning * into v_row;

  if v_row.id is null then
    raise exception 'not authorized or no linked member';
  end if;
  return v_row;
end;
$$;

-- 応募フォームから、アカウント作成と同時に会員データを作る（新しい応募専用の一体化フロー）
create or replace function public.create_my_member(
  p_category text, p_name text, p_contact text, p_address text,
  p_lat double precision, p_lng double precision, p_url text, p_message text
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_email text := (select email from auth.users where id = auth.uid());
  v_row members;
begin
  if v_email is null then
    raise exception 'not authenticated';
  end if;

  if exists (select 1 from members where owner_id = auth.uid()) then
    raise exception 'already applied';
  end if;

  insert into members (category, name, contact, address, lat, lng, url, message, email, owner_id, status)
  values (p_category, p_name, p_contact, p_address, p_lat, p_lng, p_url, p_message, v_email, auth.uid(), 'pending')
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

grant execute on function public.create_my_member(text,text,text,text,double precision,double precision,text,text) to authenticated;

grant execute on function public.claim_member() to authenticated;
grant execute on function public.get_my_member() to authenticated;
grant execute on function public.update_my_member(text,text,text,text,double precision,double precision,text,text) to authenticated;

-- 既存会員のメールアドレスを、連絡先(contact)欄からベストエフォートで抽出しておく
-- （新規応募からは専用のemail欄に保存されるので、これは移行時の一度きりの処置）
update members
set email = substring(contact from '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}')
where email is null and contact is not null;

-- ------------------------------------------------------------
-- 動作確認用のサンプルデータ（不要であれば削除してください）
-- ------------------------------------------------------------
insert into events (event_date, guest_name, theme, detail, url, status) values
  ('2026-05-18', '愛菜ファームSin 遠山克彦さんと和咲美 梅ちゃんの座談会', null, null,
    'https://satoyama3.my.canva.site/talk3', 'done'),
  ('2026-09-28', 'MIROC BEER 岩城知明さんと和咲美 梅ちゃんの座談会', null, null,
    'https://satoyama3.my.canva.site/talk44', 'upcoming'),
  ('2026-10-26', '空手の達人であり歌手さんと和咲美 梅ちゃんの座談会', null, null,
    'https://satoyama3.my.canva.site/talk5', 'upcoming'),
  ('2026-12-14', '達磨草履工房さんと和咲美でのリトリート', '（12/14(月)・12/15(火)）', null,
    'https://satoyama3.my.canva.site/talk6', 'upcoming');

insert into members (category, name, contact, address, lat, lng, url, member_type, status) values
  ('個人', '超人', null, null, null, null, null, 'general', 'approved'),
  ('団体・会社・企業', '達磨草履工房', null,
    '香川県仲多度郡まんのう町勝浦892番地', 34.0880579, 133.9916719,
    'https://www.instagram.com/dharmakoubou/?hl=ja', 'artisan', 'approved'),
  ('団体・会社・企業', 'MIROCビール', 'info@miroc-beer.com / 0877-43-7067',
    '香川県丸亀市北平山町2-5-15', 34.2888128, 133.7982421,
    'https://www.miroc-beer.com/', 'artisan', 'approved'),
  ('団体・会社・企業', '愛菜ファーム Sin', null,
    '香川県丸亀市飯山町真時555', 34.2582117, 133.8473823,
    'https://www.facebook.com/aisaifarmsin/', 'artisan', 'approved'),
  ('団体・会社・企業', '和咲美', null,
    '岡山県美作市真加部1057-4', 35.0796259, 134.1870792,
    'https://wasabi-mimasaka.com/', 'artisan', 'approved');

-- ------------------------------------------------------------
-- 補足：lat/lng は町域レベルの目安座標です（番地までは正確ではありません）。
-- 新しい会員を地図に載せたい場合は、Googleマップで場所を右クリックし
-- 表示される緯度・経度をコピーして lat / lng 列に入力してください。
-- ------------------------------------------------------------
