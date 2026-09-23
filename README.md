# NEON ENGLISH — GitHub Pages Course Platform

A flat-file GCSE English revision site designed for GitHub Pages. Theme: black + white + neon green + violet.

## Included
- Five course tiers copied from the business spreadsheet
- Higher price = longer access: Standard 14 days, Pro 21, Plus 30, Premium 60, Plus-Premium 180
- English Language Paper 1 + Paper 2 taught in the course practice order **Q5 → Q4 → Q3 → Q2 → Q1**
- Paper 2 Q5 interactive **Presently → Personally → Publicly → Predictably** builder plus the supplied layout image
- English Literature Paper 1 + Paper 2 revision content
- Interactive quizzes, progress, Quote Flip, Question Order Sprint, P4 Builder and Technique Match
- Supabase login + admin role + timed course enrolments
- Control Room for pricing, access days, lessons, quiz questions, enrolments, orders and announcements
- Payment-link fields and order tables ready for payment setup later

## 1. Upload to GitHub
Upload every file in this ZIP directly to the repository root. There are no folders.

In GitHub: **Settings → Pages → Deploy from a branch → main / root**.
Your free address will be similar to `https://YOURNAME.github.io/YOUR-REPO/`.

## 2. Create Supabase
Create a Supabase project. In **SQL Editor**, paste and run `setup.sql`.

Then open **Project Settings → API** and copy:
- Project URL
- anon / public key

Put them in `config.js`.

**Never put the service_role key in config.js or GitHub.** The anon key is designed to be public when Row Level Security is configured correctly.

## 3. Make your admin login
Open the public site and sign up with the email you want to use as the owner.

Then run this in Supabase SQL Editor, replacing the email:

```sql
update public.profiles
set is_admin = true
where id = (select id from auth.users where lower(email)=lower('YOUR-EMAIL@example.com'));
```

Now open `admin.html` and log in. Your admin account automatically has access to every course.

## 4. Demo mode
`config.js` starts with `demoMode: true`. This shows a **demo unlock on this device** button so you can test course pages before payment setup.

Before public launch, change it to:

```js
demoMode: false
```

## 5. Payments — next step
The site intentionally does **not** contain payment secrets. GitHub Pages is a static host, so secure checkout completion needs a payment provider plus a server-side webhook (for example a Supabase Edge Function).

The database already includes:
- `orders`
- `enrollments`
- `courses.payment_url`
- timed expiry dates

That means the next payment step can create an order and automatically grant the purchased course for its configured number of days.

Because the site owner is under 18, set up the payment account with a parent/guardian and follow the provider's age requirements.

## 6. Q5 course framework
The uploaded Paper 2 Q5 sheet is included as `q5-layout.png`. The typed lesson turns the same idea into an interactive planning scaffold:
**Presently → Personally → Publicly → Predictably**.

The site labels the Q5→Q1 sequence as a **course revision strategy**, not an AQA requirement.

## Official specification links
- AQA English Language 8700: https://www.aqa.org.uk/subjects/english/gcse/english-8700/specification/specification-at-a-glance
- AQA English Literature 8702: https://www.aqa.org.uk/subjects/english/gcse/english-8702/specification/specification-at-a-glance

## Copyright / branding note
NEON ENGLISH is independent and is not affiliated with or endorsed by AQA. Avoid uploading AQA logos, full copyrighted papers, mark schemes, modern-text extracts or anthology poems without permission. Use your own original practice material.
