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
  contact text,                 -- 連絡先（旧・email/phone統合欄。互換のため残置、新規は使わない）
  phone text,                   -- 電話番号
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
-- alter table members add column if not exists phone text;

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

-- membersとprofilesを統合済み。以降このセクションは「profiles」が本体で、
-- 「members」は未ログインの応募者を一時的に受け止めるだけの受付台帳。
-- ログイン直後にclaim_memberを1回呼ぶと、該当するmembers行があればprofilesへ
-- 完全に統合（コピー＋members側は削除）される。
drop function if exists public.claim_member();
drop function if exists public.get_my_member();
drop function if exists public.update_my_member(text,text,text,text,double precision,double precision,text,text);
drop function if exists public.create_my_member(text,text,text,text,double precision,double precision,text,text);

create or replace function public.claim_member()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_email text := (select email from auth.users where id = auth.uid());
  v_member members;
  v_profile profiles;
begin
  if v_email is null then
    raise exception 'not authenticated';
  end if;

  -- すでにprofiles側に統合済み（shinEDOのstatusを持っている）ならそれを返す
  select * into v_profile from profiles where id = auth.uid() and status is not null;
  if found then
    return to_jsonb(v_profile);
  end if;

  -- 未紐付のmembers行（応募したがまだログインしていない人）を探す
  select * into v_member from members where email = v_email and owner_id is null limit 1;
  if not found then
    return null;
  end if;

  insert into public.profiles (id, name, job, area, message, lat, lng, email, category, phone, url, member_type, status)
  values (
    auth.uid(), v_member.name, coalesce(v_member.category, ''), coalesce(v_member.address, ''),
    coalesce(v_member.message, ''), v_member.lat, v_member.lng, v_email,
    v_member.category, v_member.phone, v_member.url, v_member.member_type, v_member.status
  )
  on conflict (id) do update set
    category = excluded.category,
    phone = excluded.phone,
    url = excluded.url,
    member_type = excluded.member_type,
    status = excluded.status,
    area = coalesce(nullif(profiles.area, ''), excluded.area),
    lat = coalesce(profiles.lat, excluded.lat),
    lng = coalesce(profiles.lng, excluded.lng),
    email = coalesce(profiles.email, excluded.email);

  delete from members where id = v_member.id;

  select * into v_profile from profiles where id = auth.uid();
  return to_jsonb(v_profile);
end;
$$;

-- 自分に紐付いているshinEDO会員情報を取得（profilesのstatusが設定されている人のみ）
create or replace function public.get_my_member()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_row profiles;
begin
  select * into v_row from profiles where id = auth.uid() and status is not null;
  if not found then
    return null;
  end if;
  return to_jsonb(v_row);
end;
$$;

-- 自分の会員情報を編集（status・member_type・is_admin・is_paidは変更不可）
create or replace function public.update_my_member(
  p_name text, p_category text, p_phone text, p_address text,
  p_lat double precision, p_lng double precision, p_url text, p_message text
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_email text := (select email from auth.users where id = auth.uid());
  v_row profiles;
begin
  if v_email is null then
    raise exception 'not authenticated';
  end if;

  insert into public.profiles (id, name, category, phone, area, lat, lng, url, message, email, job, member_type, status)
  values (auth.uid(), p_name, p_category, coalesce(p_phone, ''), p_address, p_lat, p_lng, coalesce(p_url, ''), coalesce(p_message, ''), v_email, coalesce(p_category, ''), 'general', 'pending')
  on conflict (id) do update set
    name = p_name,
    category = p_category,
    phone = coalesce(p_phone, ''),
    area = p_address,
    lat = p_lat,
    lng = p_lng,
    url = coalesce(p_url, ''),
    message = coalesce(p_message, ''),
    job = coalesce(nullif(profiles.job, ''), p_category),
    status = coalesce(profiles.status, 'pending'),
    email = coalesce(profiles.email, v_email)
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

grant execute on function public.claim_member() to authenticated;
grant execute on function public.get_my_member() to authenticated;
grant execute on function public.update_my_member(text,text,text,text,double precision,double precision,text,text) to authenticated;

-- shinEDO管理画面用：profilesのうちshinEDOに紐づく行（statusがある行）を、
-- email列も含めて一覧取得する（profiles.emailは一般ユーザーからは見えない列のため、
-- 管理者チェック付きのこの関数経由でのみ取得できる）
create or replace function public.admin_list_members()
returns setof profiles
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from admins where user_id = auth.uid())
     and not coalesce((select is_admin from profiles where id = auth.uid()), false) then
    raise exception 'not authorized';
  end if;

  return query
    select * from profiles
    where status is not null
    order by (status = 'pending') desc, created_at desc;
end;
$$;

grant execute on function public.admin_list_members() to authenticated;

-- 既存会員のメールアドレス・電話番号を、連絡先(contact)欄からベストエフォートで抽出しておく
-- （新規応募からは専用のemail/phone欄に保存されるので、これは移行時の一度きりの処置）
update members
set email = substring(contact from '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}')
where email is null and contact is not null;

update members
set phone = substring(contact from '0[0-9]{1,4}-?[0-9]{1,4}-?[0-9]{3,4}')
where phone is null and contact is not null;

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

-- ------------------------------------------------------------
-- admins統合の取りこぼし修正：
-- members/eventsのRLSと管理者関数が、古いadminsテーブルの有無だけを
-- チェックしていた。OUEN-APP側の管理画面で「管理者にする」を押すと
-- profiles.is_adminだけが立ってadminsテーブルには入らないため、
-- そちらだけで管理者になった人はmembers/eventsを操作できなかった
-- （RLSは権限不足時にエラーを出さず0件ヒットとして黙って失敗する）。
-- admins在籍 または profiles.is_admin のどちらかで管理者と認める
-- 共通関数に差し替える。
-- ------------------------------------------------------------
create or replace function public.is_shinedo_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where user_id = auth.uid())
      or coalesce((select is_admin from profiles where id = auth.uid()), false);
$$;

drop policy if exists "members: admin read all" on members;
create policy "members: admin read all"
  on members for select
  to authenticated
  using ( public.is_shinedo_admin() );

drop policy if exists "members: admin update" on members;
create policy "members: admin update"
  on members for update
  to authenticated
  using ( public.is_shinedo_admin() )
  with check ( public.is_shinedo_admin() );

drop policy if exists "members: admin delete" on members;
create policy "members: admin delete"
  on members for delete
  to authenticated
  using ( public.is_shinedo_admin() );

drop policy if exists "events: admin read" on events;
create policy "events: admin read"
  on events for select
  to authenticated
  using ( public.is_shinedo_admin() );

drop policy if exists "events: admin insert" on events;
create policy "events: admin insert"
  on events for insert
  to authenticated
  with check ( public.is_shinedo_admin() );

drop policy if exists "events: admin update" on events;
create policy "events: admin update"
  on events for update
  to authenticated
  using ( public.is_shinedo_admin() )
  with check ( public.is_shinedo_admin() );

drop policy if exists "events: admin delete" on events;
create policy "events: admin delete"
  on events for delete
  to authenticated
  using ( public.is_shinedo_admin() );

create or replace function public.list_admins()
returns table (user_id uuid, email text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_shinedo_admin() then
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
  if not public.is_shinedo_admin() then
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
  if not public.is_shinedo_admin() then
    raise exception 'not authorized';
  end if;

  select id into target_id from auth.users where email = target_email;
  if target_id is null then
    raise exception 'ユーザーが見つかりません';
  end if;

  delete from admins where user_id = target_id;
end;
$$;

grant execute on function public.is_shinedo_admin() to authenticated;

-- ------------------------------------------------------------
-- members/adminsテーブルを完全に廃止する（最終段階）。
-- 新規登録は既にprofilesへ直接作られるようになっており、membersは
-- 未統合の古い応募データを一時的に保持するだけの台帳、adminsは
-- profiles.is_adminへ移行済みの管理者フラグの旧置き場でしかない。
-- 両テーブルをまだ参照している関数を先に置き換えてから、最後にDROPする。
-- ------------------------------------------------------------

-- 念のため、adminsテーブルにしか記録されていない管理者をprofiles.is_adminへ最終コピー
update profiles set is_admin = true
where id in (select user_id from admins) and coalesce(is_admin, false) = false;

create or replace function public.is_shinedo_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false);
$$;

create or replace function public.claim_member()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_row profiles;
begin
  select * into v_row from profiles where id = auth.uid() and status is not null;
  if not found then
    return null;
  end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.admin_list_members()
returns setof profiles
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_shinedo_admin() then
    raise exception 'not authorized';
  end if;

  return query
    select * from profiles
    where status is not null
    order by (status = 'pending') desc, created_at desc;
end;
$$;

create or replace function public.list_admins()
returns table (user_id uuid, email text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_shinedo_admin() then
    raise exception 'not authorized';
  end if;

  return query
  select p.id, u.email::text
  from profiles p
  join auth.users u on u.id = p.id
  where p.is_admin;
end;
$$;

create or replace function public.grant_admin(target_email text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  target_id uuid;
begin
  if not public.is_shinedo_admin() then
    raise exception 'not authorized';
  end if;

  select id into target_id from auth.users where email = target_email;
  if target_id is null then
    raise exception 'そのメールアドレスのユーザーが見つかりません（先にSupabase AuthでUserを作成してください）';
  end if;

  update profiles set is_admin = true where id = target_id;
  if not found then
    raise exception 'そのユーザーはまだprofilesに登録されていません（一度mypage.htmlでログインしてもらってください）';
  end if;
end;
$$;

create or replace function public.revoke_admin(target_email text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  target_id uuid;
begin
  if not public.is_shinedo_admin() then
    raise exception 'not authorized';
  end if;

  select id into target_id from auth.users where email = target_email;
  if target_id is null then
    raise exception 'ユーザーが見つかりません';
  end if;

  update profiles set is_admin = false where id = target_id;
end;
$$;

drop table if exists members cascade;
drop table if exists admins cascade;

-- ------------------------------------------------------------
-- ニュース機能：admin.htmlで投稿し、HPトップに表示する
-- ------------------------------------------------------------
create table if not exists news (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text,
  content text,
  news_date date,
  created_at timestamptz not null default now()
);
alter table news enable row level security;

create policy "news: public read"
  on news for select
  to public
  using ( true );

create policy "news: admin insert"
  on news for insert
  to authenticated
  with check ( public.is_shinedo_admin() );

create policy "news: admin update"
  on news for update
  to authenticated
  using ( public.is_shinedo_admin() )
  with check ( public.is_shinedo_admin() );

create policy "news: admin delete"
  on news for delete
  to authenticated
  using ( public.is_shinedo_admin() );

-- 動作確認用ダミーデータ（確認できたら管理画面から削除してOK）
insert into news (title, category, content, news_date) values
  ('shinEDO projectのウェブサイトを公開しました', 'お知らせ', 'これはダミーのニュースです。管理ページの「ニュース」タブから編集・削除できます。', current_date);
