-- NEON ENGLISH — Supabase setup
-- Run this whole file once in Supabase SQL Editor.
-- Then create your account in the site and use the admin promotion command in README.md.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  focus text not null,
  description text not null default '',
  price numeric(8,2) not null default 0,
  duration_days integer not null default 30 check(duration_days > 0),
  sort_order integer not null default 0,
  payment_url text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.lessons (
  id uuid primary key default gen_random_uuid(),
  course_slug text not null references public.courses(slug) on update cascade on delete cascade,
  title text not null,
  lesson_type text not null default 'lesson',
  body text not null default '',
  sort_order integer not null default 0,
  free_preview boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  course_slug text not null references public.courses(slug) on update cascade on delete cascade,
  question text not null,
  options text[] not null,
  correct_index integer not null default 0,
  explanation text not null default '',
  sort_order integer not null default 0
);

create table if not exists public.enrollments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  user_email text,
  course_slug text not null references public.courses(slug) on update cascade on delete cascade,
  starts_at timestamptz not null default now(),
  expires_at timestamptz not null,
  source text not null default 'admin',
  created_at timestamptz not null default now()
);
create unique index if not exists enrollments_user_course_uq on public.enrollments(user_id,course_slug);

create table if not exists public.progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  completed boolean not null default true,
  score numeric,
  updated_at timestamptz not null default now(),
  primary key(user_id,lesson_id)
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  customer_email text,
  course_slug text references public.courses(slug) on update cascade on delete set null,
  amount numeric(8,2) not null default 0,
  currency text not null default 'GBP',
  status text not null default 'pending',
  provider text,
  provider_reference text unique,
  created_at timestamptz not null default now()
);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email) values(new.id,new.email) on conflict(id) do update set email=excluded.email;
  return new;
end;$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select is_admin from public.profiles where id=auth.uid()),false);
$$;

create or replace function public.has_course_access(p_course_slug text) returns boolean language sql stable security definer set search_path=public as $$
  select public.is_admin() or exists(
    select 1 from public.enrollments e where e.user_id=auth.uid() and e.course_slug=p_course_slug and e.expires_at>now()
  );
$$;

create or replace function public.grant_access_by_email(p_email text,p_course_slug text,p_days integer) returns void language plpgsql security definer set search_path=public as $$
declare uid uuid; em text;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  select id,email into uid,em from auth.users where lower(email)=lower(p_email) limit 1;
  if uid is null then raise exception 'No account found for that email. Ask the learner to sign up first.'; end if;
  insert into public.enrollments(user_id,user_email,course_slug,starts_at,expires_at,source)
  values(uid,em,p_course_slug,now(),now()+make_interval(days=>greatest(p_days,1)),'admin')
  on conflict(user_id,course_slug) do update set starts_at=now(),expires_at=excluded.expires_at,user_email=excluded.user_email,source='admin';
end;$$;

-- RLS
alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.lessons enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.enrollments enable row level security;
alter table public.progress enable row level security;
alter table public.orders enable row level security;
alter table public.announcements enable row level security;

drop policy if exists profiles_self_select on public.profiles; create policy profiles_self_select on public.profiles for select using(id=auth.uid() or public.is_admin());
drop policy if exists profiles_admin_all on public.profiles; create policy profiles_admin_all on public.profiles for all using(public.is_admin()) with check(public.is_admin());

drop policy if exists courses_read on public.courses; create policy courses_read on public.courses for select using(active or public.is_admin());
drop policy if exists courses_admin on public.courses; create policy courses_admin on public.courses for all using(public.is_admin()) with check(public.is_admin());

drop policy if exists lessons_read on public.lessons; create policy lessons_read on public.lessons for select using(free_preview or public.has_course_access(course_slug));
drop policy if exists lessons_admin on public.lessons; create policy lessons_admin on public.lessons for all using(public.is_admin()) with check(public.is_admin());

drop policy if exists quiz_read on public.quiz_questions; create policy quiz_read on public.quiz_questions for select using(public.has_course_access(course_slug));
drop policy if exists quiz_admin on public.quiz_questions; create policy quiz_admin on public.quiz_questions for all using(public.is_admin()) with check(public.is_admin());

drop policy if exists enrollments_self on public.enrollments; create policy enrollments_self on public.enrollments for select using(user_id=auth.uid() or public.is_admin());
drop policy if exists enrollments_admin on public.enrollments; create policy enrollments_admin on public.enrollments for all using(public.is_admin()) with check(public.is_admin());

drop policy if exists progress_self on public.progress; create policy progress_self on public.progress for all using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());

drop policy if exists orders_self on public.orders; create policy orders_self on public.orders for select using(user_id=auth.uid() or public.is_admin());
drop policy if exists orders_admin on public.orders; create policy orders_admin on public.orders for all using(public.is_admin()) with check(public.is_admin());

drop policy if exists announcements_read on public.announcements; create policy announcements_read on public.announcements for select using(active or public.is_admin());
drop policy if exists announcements_admin on public.announcements; create policy announcements_admin on public.announcements for all using(public.is_admin()) with check(public.is_admin());

-- Seed courses
insert into public.courses(slug,name,focus,description,price,duration_days,sort_order,active) values
  ('standard','Standard','English Literature — AQA','Focused Literature revision with guided essays, quote recall and core exam skills.',4.99,14,1,true),
  ('pro','Pro','English Language — AQA','English Language Paper 1 and Paper 2 taught in the course strategy order Q5 → Q4 → Q3 → Q2 → Q1.',5.99,21,2,true),
  ('plus','Plus','A bit of Literature + Language','A balanced set of Literature and Language essentials for students who want both without the full library.',7.99,30,3,true),
  ('premium','Premium','Literature + Language','A longer-access course covering both subjects in shorter, digestible lessons.',9.99,60,4,true),
  ('plus-premium','Plus-Premium','Full Literature + Language','The complete revision library: detailed lessons, all interactive tools, games, quizzes and exam planning.',14.99,180,5,true)
on conflict(slug) do update set name=excluded.name,focus=excluded.focus,description=excluded.description,price=excluded.price,duration_days=excluded.duration_days,sort_order=excluded.sort_order;

-- Re-seed starter lessons and quizzes. Remove these two delete lines if you have already customised content.
delete from public.lessons;
delete from public.quiz_questions;
insert into public.lessons(course_slug,title,lesson_type,body,sort_order,free_preview) values
  ('standard','Literature Exam Map','lesson','Know the two AQA Literature papers before you revise. Paper 1 covers Shakespeare and the 19th-century novel. Paper 2 covers the modern text, anthology poetry and unseen poetry.

Your job in Literature is not to retell the story. Build a clear interpretation, support it with precise references, analyse the writer’s choices and connect context only where it genuinely helps the argument.',1,false),
  ('standard','Build a Literature Paragraph','lesson','Use a simple four-part paragraph: IDEA → EVIDENCE → METHOD → WHY IT MATTERS.

IDEA: answer the question with an interpretation.
EVIDENCE: use a short quotation or precise reference.
METHOD: identify a useful language, form or structure choice.
WHY IT MATTERS: explain the effect and connect back to the question.

Do not force terminology into every sentence. A strong explanation matters more than naming a complicated technique.',2,false),
  ('standard','Macbeth: Ambition, Power and Guilt','lesson','Revision focus: track how ambition changes Macbeth, how Lady Macbeth challenges expectations, and how guilt is shown through repeated images of blood, sleep and darkness.

Try this planning task: write three different thesis statements for a question about ambition. Each thesis should make a slightly different argument rather than repeating the same point.',3,false),
  ('standard','A Christmas Carol: Change and Responsibility','lesson','Revision focus: Scrooge’s transformation, social responsibility, poverty and family. Track how Dickens moves Scrooge from isolation to participation.

Essay habit: connect each paragraph to a stage of change. This creates a line of argument across the whole response instead of isolated points.',4,false),
  ('standard','Anthology Poetry: Compare Ideas, Not Just Devices','lesson','Start with the big comparison: what idea does each poem present and where do they agree or differ? Then compare methods that create those ideas.

A useful comparison sentence: “Both poems present ___, but while Poem A suggests ___, Poem B presents ___.”

Use the poems your school studies. This course does not reproduce copyrighted anthology poems.',5,false),
  ('standard','Unseen Poetry: First Read to Final Paragraph','lesson','First read: identify the situation, speaker and broad feeling. Second read: mark changes, contrasts and striking images. Third read: choose the best evidence for your argument.

Do not try to decode every line. Build a defensible interpretation from the strongest evidence you can explain.',6,false),
  ('standard','Quotation Recall Without Panic','lesson','Learn short, flexible quotations rather than huge chunks. Attach each quotation to two or three themes so it can work in different questions.

Game technique: cover the second half of a quotation and recall it; then explain one method and one possible interpretation.',7,false),
  ('standard','Literature Final Check','checklist','Before you finish an essay, check: Have I answered the exact question? Is there a clear argument? Did I analyse methods rather than just spot them? Did I use evidence? Did I keep returning to the writer’s purpose and the question?',8,false),
  ('pro','Paper 1: Learn the Course Order','lesson','For this course, you practise Paper 1 backwards: Q5 → Q4 → Q3 → Q2 → Q1. This is a revision strategy, not an AQA rule. In the real exam you may answer in any order, so practise the order that helps you manage time best.

Q5: extended creative writing.
Q4: evaluation.
Q3: structure.
Q2: language.
Q1: retrieval.',1,false),
  ('pro','Paper 1 Q5: Creative Writing','interactive','Plan before you write. Pick one clear atmosphere and a simple shape for the piece: OPEN → DEVELOP → SHIFT → END.

Description: control viewpoint, sensory detail and sentence length.
Narrative: keep the plot small enough to finish well.

Try the 5-minute plan tool in the Games section before writing a full response.',2,false),
  ('pro','Paper 1 Q4: Evaluation','lesson','Make a judgement, then prove it. Use the statement in the question as something to test rather than something to copy.

A strong paragraph often does three things: gives a clear judgement, selects precise evidence, and explains how the writer’s choices shape the reader’s response.',3,false),
  ('pro','Paper 1 Q3: Structure','lesson','Think movement, focus and change. Ask: Where does the text begin? What becomes important? When does the focus shift? What changes by the ending?

Structure is not just “short sentence” or “paragraph”. Explain how information is organised across the text.',4,false),
  ('pro','Paper 1 Q2: Language','lesson','Choose a small amount of evidence and zoom in properly. Explain connotations, imagery, contrast, verbs, adjectives or sound only when they help your interpretation.

Avoid the empty phrase “this makes the reader want to read on”. Say what the language makes the reader understand, imagine or feel and why.',5,false),
  ('pro','Paper 1 Q1: Retrieval','lesson','Keep it literal. Find four distinct things from the specified lines. Do not analyse. Do not add ideas that are not clearly supported by the extract.

Accuracy beats complexity here.',6,false),
  ('pro','Paper 2: Learn the Course Order','lesson','For this course, you practise Paper 2 backwards: Q5 → Q4 → Q3 → Q2 → Q1. This is a revision strategy rather than an AQA requirement.

Q5: viewpoint writing.
Q4: compare viewpoints and methods.
Q3: language analysis.
Q2: summary/inference across two sources.
Q1: retrieval.',7,false),
  ('pro','Paper 2 Q5: Viewpoint Writing — P4 Framework','interactive','Use the framework from your course sheet as a planning scaffold: PRESENTLY → PERSONALLY → PUBLICLY → PREDICTABLY.

PRESENTLY: establish your viewpoint and hook the audience.
PERSONALLY: make the issue human with a believable personal perspective.
PUBLICLY: widen out to society, examples or evidence.
PREDICTABLY: acknowledge an opposing view, rebut it, then finish decisively.

Match the form too: article = headline/subheading if useful; letter = appropriate opening and sign-off; speech = direct address and a clear closing.

The full layout image you supplied is built into this lesson below the interactive builder.',8,false),
  ('pro','Paper 2 Q4: Compare Viewpoints','lesson','Compare what the writers think and how they communicate it. Keep both sources in the paragraph rather than writing half an essay on Source A and then half on Source B.

A useful pattern: viewpoint A → evidence/method → viewpoint B → evidence/method → comparison.',9,false),
  ('pro','Paper 2 Q3: Language','lesson','Analyse how the writer uses language in the named source. Select evidence that gives you something specific to explain. Look for patterns as well as single words.

Your explanation should connect the writer’s language choice to the viewpoint or impression created.',10,false),
  ('pro','Paper 2 Q2: Summary and Inference','lesson','Work with both sources. Identify a clear difference or similarity, support it from each source, then infer what that evidence suggests.

Do not drift into detailed language analysis: the focus is what you learn from the sources and how those ideas compare.',11,false),
  ('pro','Paper 2 Q1: Retrieval','lesson','Read the statements carefully and check them against the specified part of the source. This question rewards precise retrieval, not interpretation.

Do a final scan before moving on so you do not lose an easy mark through rushing.',12,false),
  ('pro','Language Timing and Reset Strategy','checklist','Build a timing plan you can actually follow. Practise in chunks before attempting a whole paper. If a question runs over time, leave space and move on; protect the high-mark writing task rather than sacrificing it accidentally.',13,false),
  ('plus','Both Subjects: The 30-Minute Revision Loop','lesson','A simple mixed session: 10 minutes recall, 10 minutes exam practice, 10 minutes self-check. Alternate Literature and Language so you revise knowledge and exam technique across the week.',1,false),
  ('plus','Build a Literature Paragraph','lesson','Use a simple four-part paragraph: IDEA → EVIDENCE → METHOD → WHY IT MATTERS.

IDEA: answer the question with an interpretation.
EVIDENCE: use a short quotation or precise reference.
METHOD: identify a useful language, form or structure choice.
WHY IT MATTERS: explain the effect and connect back to the question.

Do not force terminology into every sentence. A strong explanation matters more than naming a complicated technique.',2,false),
  ('plus','Macbeth: Ambition, Power and Guilt','lesson','Revision focus: track how ambition changes Macbeth, how Lady Macbeth challenges expectations, and how guilt is shown through repeated images of blood, sleep and darkness.

Try this planning task: write three different thesis statements for a question about ambition. Each thesis should make a slightly different argument rather than repeating the same point.',3,false),
  ('plus','Anthology Poetry: Compare Ideas, Not Just Devices','lesson','Start with the big comparison: what idea does each poem present and where do they agree or differ? Then compare methods that create those ideas.

A useful comparison sentence: “Both poems present ___, but while Poem A suggests ___, Poem B presents ___.”

Use the poems your school studies. This course does not reproduce copyrighted anthology poems.',4,false),
  ('plus','Paper 1: Learn the Course Order','lesson','For this course, you practise Paper 1 backwards: Q5 → Q4 → Q3 → Q2 → Q1. This is a revision strategy, not an AQA rule. In the real exam you may answer in any order, so practise the order that helps you manage time best.

Q5: extended creative writing.
Q4: evaluation.
Q3: structure.
Q2: language.
Q1: retrieval.',5,false),
  ('plus','Paper 1 Q5: Creative Writing','interactive','Plan before you write. Pick one clear atmosphere and a simple shape for the piece: OPEN → DEVELOP → SHIFT → END.

Description: control viewpoint, sensory detail and sentence length.
Narrative: keep the plot small enough to finish well.

Try the 5-minute plan tool in the Games section before writing a full response.',6,false),
  ('plus','Paper 2: Learn the Course Order','lesson','For this course, you practise Paper 2 backwards: Q5 → Q4 → Q3 → Q2 → Q1. This is a revision strategy rather than an AQA requirement.

Q5: viewpoint writing.
Q4: compare viewpoints and methods.
Q3: language analysis.
Q2: summary/inference across two sources.
Q1: retrieval.',7,false),
  ('plus','Paper 2 Q5: Viewpoint Writing — P4 Framework','interactive','Use the framework from your course sheet as a planning scaffold: PRESENTLY → PERSONALLY → PUBLICLY → PREDICTABLY.

PRESENTLY: establish your viewpoint and hook the audience.
PERSONALLY: make the issue human with a believable personal perspective.
PUBLICLY: widen out to society, examples or evidence.
PREDICTABLY: acknowledge an opposing view, rebut it, then finish decisively.

Match the form too: article = headline/subheading if useful; letter = appropriate opening and sign-off; speech = direct address and a clear closing.

The full layout image you supplied is built into this lesson below the interactive builder.',8,false),
  ('plus','Upgrade a Weak Answer','interactive','Take a weak paragraph and improve it in three passes: 1) make the point answer the question, 2) make the evidence precise, 3) deepen the explanation. The goal is not to make sentences longer — it is to make the reasoning clearer.',9,false),
  ('plus','Exam-Day Checklist','checklist','Before the exam: know your paper, bring the correct equipment, and avoid last-minute overload. During the paper: read the question wording carefully, watch the clock, leave space if needed and return. At the end: use spare minutes to check your writing rather than starting a new idea.',10,false),
  ('premium','Both Subjects: The 30-Minute Revision Loop','lesson','A simple mixed session: 10 minutes recall, 10 minutes exam practice, 10 minutes self-check. Alternate Literature and Language so you revise knowledge and exam technique across the week.',1,false),
  ('premium','Literature Exam Map','lesson','Know the two AQA Literature papers before you revise. Paper 1 covers Shakespeare and the 19th-century novel. Paper 2 covers the modern text, anthology poetry and unseen poetry.

Your job in Literature is not to retell the story. Build a clear interpretation, support it with precise references, analyse the writer’s choices and connect context only where it genuinely helps the argument.',2,false),
  ('premium','Build a Literature Paragraph','lesson','Use a simple four-part paragraph: IDEA → EVIDENCE → METHOD → WHY IT MATTERS.

IDEA: answer the question with an interpretation.
EVIDENCE: use a short quotation or precise reference.
METHOD: identify a useful language, form or structure choice.
WHY IT MATTERS: explain the effect and connect back to the question.

Do not force terminology into every sentence. A strong explanation matters more than naming a complicated technique.',3,false),
  ('premium','Macbeth: Ambition, Power and Guilt','lesson','Revision focus: track how ambition changes Macbeth, how Lady Macbeth challenges expectations, and how guilt is shown through repeated images of blood, sleep and darkness.

Try this planning task: write three different thesis statements for a question about ambition. Each thesis should make a slightly different argument rather than repeating the same point.',4,false),
  ('premium','A Christmas Carol: Change and Responsibility','lesson','Revision focus: Scrooge’s transformation, social responsibility, poverty and family. Track how Dickens moves Scrooge from isolation to participation.

Essay habit: connect each paragraph to a stage of change. This creates a line of argument across the whole response instead of isolated points.',5,false),
  ('premium','Anthology Poetry: Compare Ideas, Not Just Devices','lesson','Start with the big comparison: what idea does each poem present and where do they agree or differ? Then compare methods that create those ideas.

A useful comparison sentence: “Both poems present ___, but while Poem A suggests ___, Poem B presents ___.”

Use the poems your school studies. This course does not reproduce copyrighted anthology poems.',6,false),
  ('premium','Unseen Poetry: First Read to Final Paragraph','lesson','First read: identify the situation, speaker and broad feeling. Second read: mark changes, contrasts and striking images. Third read: choose the best evidence for your argument.

Do not try to decode every line. Build a defensible interpretation from the strongest evidence you can explain.',7,false),
  ('premium','Paper 1: Learn the Course Order','lesson','For this course, you practise Paper 1 backwards: Q5 → Q4 → Q3 → Q2 → Q1. This is a revision strategy, not an AQA rule. In the real exam you may answer in any order, so practise the order that helps you manage time best.

Q5: extended creative writing.
Q4: evaluation.
Q3: structure.
Q2: language.
Q1: retrieval.',8,false),
  ('premium','Paper 1 Q5: Creative Writing','interactive','Plan before you write. Pick one clear atmosphere and a simple shape for the piece: OPEN → DEVELOP → SHIFT → END.

Description: control viewpoint, sensory detail and sentence length.
Narrative: keep the plot small enough to finish well.

Try the 5-minute plan tool in the Games section before writing a full response.',9,false),
  ('premium','Paper 1 Q4: Evaluation','lesson','Make a judgement, then prove it. Use the statement in the question as something to test rather than something to copy.

A strong paragraph often does three things: gives a clear judgement, selects precise evidence, and explains how the writer’s choices shape the reader’s response.',10,false),
  ('premium','Paper 1 Q2: Language','lesson','Choose a small amount of evidence and zoom in properly. Explain connotations, imagery, contrast, verbs, adjectives or sound only when they help your interpretation.

Avoid the empty phrase “this makes the reader want to read on”. Say what the language makes the reader understand, imagine or feel and why.',11,false),
  ('premium','Paper 2: Learn the Course Order','lesson','For this course, you practise Paper 2 backwards: Q5 → Q4 → Q3 → Q2 → Q1. This is a revision strategy rather than an AQA requirement.

Q5: viewpoint writing.
Q4: compare viewpoints and methods.
Q3: language analysis.
Q2: summary/inference across two sources.
Q1: retrieval.',12,false),
  ('premium','Paper 2 Q5: Viewpoint Writing — P4 Framework','interactive','Use the framework from your course sheet as a planning scaffold: PRESENTLY → PERSONALLY → PUBLICLY → PREDICTABLY.

PRESENTLY: establish your viewpoint and hook the audience.
PERSONALLY: make the issue human with a believable personal perspective.
PUBLICLY: widen out to society, examples or evidence.
PREDICTABLY: acknowledge an opposing view, rebut it, then finish decisively.

Match the form too: article = headline/subheading if useful; letter = appropriate opening and sign-off; speech = direct address and a clear closing.

The full layout image you supplied is built into this lesson below the interactive builder.',13,false),
  ('premium','Paper 2 Q4: Compare Viewpoints','lesson','Compare what the writers think and how they communicate it. Keep both sources in the paragraph rather than writing half an essay on Source A and then half on Source B.

A useful pattern: viewpoint A → evidence/method → viewpoint B → evidence/method → comparison.',14,false),
  ('premium','Paper 2 Q2: Summary and Inference','lesson','Work with both sources. Identify a clear difference or similarity, support it from each source, then infer what that evidence suggests.

Do not drift into detailed language analysis: the focus is what you learn from the sources and how those ideas compare.',15,false),
  ('premium','Build Your Own Mini Mock','interactive','Pick one reading question, one writing question and one Literature paragraph. Set a strict time limit and complete all three. Then mark only three things: accuracy, explanation and time control. Repeat with a new combination next week.',16,false),
  ('premium','Exam-Day Checklist','checklist','Before the exam: know your paper, bring the correct equipment, and avoid last-minute overload. During the paper: read the question wording carefully, watch the clock, leave space if needed and return. At the end: use spare minutes to check your writing rather than starting a new idea.',17,false),
  ('plus-premium','Literature Exam Map','lesson','Know the two AQA Literature papers before you revise. Paper 1 covers Shakespeare and the 19th-century novel. Paper 2 covers the modern text, anthology poetry and unseen poetry.

Your job in Literature is not to retell the story. Build a clear interpretation, support it with precise references, analyse the writer’s choices and connect context only where it genuinely helps the argument.',1,false),
  ('plus-premium','Build a Literature Paragraph','lesson','Use a simple four-part paragraph: IDEA → EVIDENCE → METHOD → WHY IT MATTERS.

IDEA: answer the question with an interpretation.
EVIDENCE: use a short quotation or precise reference.
METHOD: identify a useful language, form or structure choice.
WHY IT MATTERS: explain the effect and connect back to the question.

Do not force terminology into every sentence. A strong explanation matters more than naming a complicated technique.',2,false),
  ('plus-premium','Macbeth: Ambition, Power and Guilt','lesson','Revision focus: track how ambition changes Macbeth, how Lady Macbeth challenges expectations, and how guilt is shown through repeated images of blood, sleep and darkness.

Try this planning task: write three different thesis statements for a question about ambition. Each thesis should make a slightly different argument rather than repeating the same point.',3,false),
  ('plus-premium','A Christmas Carol: Change and Responsibility','lesson','Revision focus: Scrooge’s transformation, social responsibility, poverty and family. Track how Dickens moves Scrooge from isolation to participation.

Essay habit: connect each paragraph to a stage of change. This creates a line of argument across the whole response instead of isolated points.',4,false),
  ('plus-premium','Anthology Poetry: Compare Ideas, Not Just Devices','lesson','Start with the big comparison: what idea does each poem present and where do they agree or differ? Then compare methods that create those ideas.

A useful comparison sentence: “Both poems present ___, but while Poem A suggests ___, Poem B presents ___.”

Use the poems your school studies. This course does not reproduce copyrighted anthology poems.',5,false),
  ('plus-premium','Unseen Poetry: First Read to Final Paragraph','lesson','First read: identify the situation, speaker and broad feeling. Second read: mark changes, contrasts and striking images. Third read: choose the best evidence for your argument.

Do not try to decode every line. Build a defensible interpretation from the strongest evidence you can explain.',6,false),
  ('plus-premium','Quotation Recall Without Panic','lesson','Learn short, flexible quotations rather than huge chunks. Attach each quotation to two or three themes so it can work in different questions.

Game technique: cover the second half of a quotation and recall it; then explain one method and one possible interpretation.',7,false),
  ('plus-premium','Literature Final Check','checklist','Before you finish an essay, check: Have I answered the exact question? Is there a clear argument? Did I analyse methods rather than just spot them? Did I use evidence? Did I keep returning to the writer’s purpose and the question?',8,false),
  ('plus-premium','Paper 1: Learn the Course Order','lesson','For this course, you practise Paper 1 backwards: Q5 → Q4 → Q3 → Q2 → Q1. This is a revision strategy, not an AQA rule. In the real exam you may answer in any order, so practise the order that helps you manage time best.

Q5: extended creative writing.
Q4: evaluation.
Q3: structure.
Q2: language.
Q1: retrieval.',9,false),
  ('plus-premium','Paper 1 Q5: Creative Writing','interactive','Plan before you write. Pick one clear atmosphere and a simple shape for the piece: OPEN → DEVELOP → SHIFT → END.

Description: control viewpoint, sensory detail and sentence length.
Narrative: keep the plot small enough to finish well.

Try the 5-minute plan tool in the Games section before writing a full response.',10,false),
  ('plus-premium','Paper 1 Q4: Evaluation','lesson','Make a judgement, then prove it. Use the statement in the question as something to test rather than something to copy.

A strong paragraph often does three things: gives a clear judgement, selects precise evidence, and explains how the writer’s choices shape the reader’s response.',11,false),
  ('plus-premium','Paper 1 Q3: Structure','lesson','Think movement, focus and change. Ask: Where does the text begin? What becomes important? When does the focus shift? What changes by the ending?

Structure is not just “short sentence” or “paragraph”. Explain how information is organised across the text.',12,false),
  ('plus-premium','Paper 1 Q2: Language','lesson','Choose a small amount of evidence and zoom in properly. Explain connotations, imagery, contrast, verbs, adjectives or sound only when they help your interpretation.

Avoid the empty phrase “this makes the reader want to read on”. Say what the language makes the reader understand, imagine or feel and why.',13,false),
  ('plus-premium','Paper 1 Q1: Retrieval','lesson','Keep it literal. Find four distinct things from the specified lines. Do not analyse. Do not add ideas that are not clearly supported by the extract.

Accuracy beats complexity here.',14,false),
  ('plus-premium','Paper 2: Learn the Course Order','lesson','For this course, you practise Paper 2 backwards: Q5 → Q4 → Q3 → Q2 → Q1. This is a revision strategy rather than an AQA requirement.

Q5: viewpoint writing.
Q4: compare viewpoints and methods.
Q3: language analysis.
Q2: summary/inference across two sources.
Q1: retrieval.',15,false),
  ('plus-premium','Paper 2 Q5: Viewpoint Writing — P4 Framework','interactive','Use the framework from your course sheet as a planning scaffold: PRESENTLY → PERSONALLY → PUBLICLY → PREDICTABLY.

PRESENTLY: establish your viewpoint and hook the audience.
PERSONALLY: make the issue human with a believable personal perspective.
PUBLICLY: widen out to society, examples or evidence.
PREDICTABLY: acknowledge an opposing view, rebut it, then finish decisively.

Match the form too: article = headline/subheading if useful; letter = appropriate opening and sign-off; speech = direct address and a clear closing.

The full layout image you supplied is built into this lesson below the interactive builder.',16,false),
  ('plus-premium','Paper 2 Q4: Compare Viewpoints','lesson','Compare what the writers think and how they communicate it. Keep both sources in the paragraph rather than writing half an essay on Source A and then half on Source B.

A useful pattern: viewpoint A → evidence/method → viewpoint B → evidence/method → comparison.',17,false),
  ('plus-premium','Paper 2 Q3: Language','lesson','Analyse how the writer uses language in the named source. Select evidence that gives you something specific to explain. Look for patterns as well as single words.

Your explanation should connect the writer’s language choice to the viewpoint or impression created.',18,false),
  ('plus-premium','Paper 2 Q2: Summary and Inference','lesson','Work with both sources. Identify a clear difference or similarity, support it from each source, then infer what that evidence suggests.

Do not drift into detailed language analysis: the focus is what you learn from the sources and how those ideas compare.',19,false),
  ('plus-premium','Paper 2 Q1: Retrieval','lesson','Read the statements carefully and check them against the specified part of the source. This question rewards precise retrieval, not interpretation.

Do a final scan before moving on so you do not lose an easy mark through rushing.',20,false),
  ('plus-premium','Language Timing and Reset Strategy','checklist','Build a timing plan you can actually follow. Practise in chunks before attempting a whole paper. If a question runs over time, leave space and move on; protect the high-mark writing task rather than sacrificing it accidentally.',21,false),
  ('plus-premium','Both Subjects: The 30-Minute Revision Loop','lesson','A simple mixed session: 10 minutes recall, 10 minutes exam practice, 10 minutes self-check. Alternate Literature and Language so you revise knowledge and exam technique across the week.',22,false),
  ('plus-premium','Upgrade a Weak Answer','interactive','Take a weak paragraph and improve it in three passes: 1) make the point answer the question, 2) make the evidence precise, 3) deepen the explanation. The goal is not to make sentences longer — it is to make the reasoning clearer.',23,false),
  ('plus-premium','Build Your Own Mini Mock','interactive','Pick one reading question, one writing question and one Literature paragraph. Set a strict time limit and complete all three. Then mark only three things: accuracy, explanation and time control. Repeat with a new combination next week.',24,false),
  ('plus-premium','Exam-Day Checklist','checklist','Before the exam: know your paper, bring the correct equipment, and avoid last-minute overload. During the paper: read the question wording carefully, watch the clock, leave space if needed and return. At the end: use spare minutes to check your writing rather than starting a new idea.',25,false);

insert into public.quiz_questions(course_slug,question,options,correct_index,explanation,sort_order) values
  ('standard','What should a Literature thesis do?',ARRAY['Retell the plot','State a clear interpretation that answers the question','List five techniques']::text[],1,'A thesis gives the essay a line of argument.',1),
  ('standard','Which is usually better quotation revision?',ARRAY['Short flexible quotations linked to themes','Memorising whole pages','Avoiding quotations completely']::text[],0,'Short, flexible evidence is easier to apply accurately.',2),
  ('standard','What is the main job of context?',ARRAY['Replace analysis','Support a relevant interpretation','Appear in every sentence']::text[],1,'Context is useful when it genuinely develops the argument.',3),
  ('pro','In this course, what order do you practise each Language paper in?',ARRAY['Q1 → Q2 → Q3 → Q4 → Q5','Q5 → Q4 → Q3 → Q2 → Q1','Q3 → Q2 → Q1 → Q5 → Q4']::text[],1,'The course deliberately teaches a backwards practice order so the extended writing task is trained first.',1),
  ('pro','What is the main focus of Paper 1 Q3?',ARRAY['Structure across the text','Retrieval only','Spelling rules']::text[],0,'Q3 focuses on how the text is structured and how focus or information changes.',2),
  ('pro','What should you do first in the P4 Paper 2 Q5 framework?',ARRAY['Predictably','Publicly','Presently']::text[],2,'Presently establishes the current issue and your viewpoint.',3),
  ('pro','For a retrieval question, what matters most?',ARRAY['Complex terminology','Accurate information from the specified lines','A long introduction']::text[],1,'Retrieval rewards precise selection, not analysis.',4),
  ('plus','A strong mixed revision session should combine…',ARRAY['Only reading notes','Recall and exam practice','Only watching videos']::text[],1,'Recall plus application helps turn knowledge into exam performance.',1),
  ('plus','When improving a paragraph, the goal is mainly to…',ARRAY['Make every sentence longer','Make the reasoning clearer','Add as many techniques as possible']::text[],1,'Clarity and precise explanation matter more than inflated wording.',2),
  ('premium','A strong mixed revision session should combine…',ARRAY['Only reading notes','Recall and exam practice','Only watching videos']::text[],1,'Recall plus application helps turn knowledge into exam performance.',1),
  ('premium','When improving a paragraph, the goal is mainly to…',ARRAY['Make every sentence longer','Make the reasoning clearer','Add as many techniques as possible']::text[],1,'Clarity and precise explanation matter more than inflated wording.',2),
  ('plus-premium','In this course, what order do you practise each Language paper in?',ARRAY['Q1 → Q2 → Q3 → Q4 → Q5','Q5 → Q4 → Q3 → Q2 → Q1','Q3 → Q2 → Q1 → Q5 → Q4']::text[],1,'The course deliberately teaches a backwards practice order so the extended writing task is trained first.',1),
  ('plus-premium','What is the main focus of Paper 1 Q3?',ARRAY['Structure across the text','Retrieval only','Spelling rules']::text[],0,'Q3 focuses on how the text is structured and how focus or information changes.',2),
  ('plus-premium','What should you do first in the P4 Paper 2 Q5 framework?',ARRAY['Predictably','Publicly','Presently']::text[],2,'Presently establishes the current issue and your viewpoint.',3),
  ('plus-premium','For a retrieval question, what matters most?',ARRAY['Complex terminology','Accurate information from the specified lines','A long introduction']::text[],1,'Retrieval rewards precise selection, not analysis.',4),
  ('plus-premium','What should a Literature thesis do?',ARRAY['Retell the plot','State a clear interpretation that answers the question','List five techniques']::text[],1,'A thesis gives the essay a line of argument.',5),
  ('plus-premium','Which is usually better quotation revision?',ARRAY['Short flexible quotations linked to themes','Memorising whole pages','Avoiding quotations completely']::text[],0,'Short, flexible evidence is easier to apply accurately.',6),
  ('plus-premium','What is the main job of context?',ARRAY['Replace analysis','Support a relevant interpretation','Appear in every sentence']::text[],1,'Context is useful when it genuinely develops the argument.',7);

insert into public.announcements(title,body,active) values('Welcome to NEON ENGLISH','The starter revision platform is live. Course content can be edited from the Control Room.',true);
